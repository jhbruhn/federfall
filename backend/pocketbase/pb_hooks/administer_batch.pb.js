/// <reference path="../pb_data/types.d.ts" />

// federfall-o3gz — one dose round over a group, in one act.
//
// The other half of prescribe_batch.pb.js (federfall-hqhg), and the half that
// recurs: writing the course is one act per course, but GIVING it is one act per
// dose. Nine birds twice a day for a week is ~126 visits to a sheet, and the
// carer is holding a syringe while they do it.
//
// So: one transaction, all rows or none — the exam.pb.js reason (federfall-lov0)
// with a clinical edge of its own. A dose round half recorded does not read as
// "some rows missing"; it reads as birds that did not get their medicine, which
// is exactly the state somebody will act on by giving a second dose.
//
// Request (JSON):
//
//   doses            [{medication, dose, weight_g_used, volume_ml}] — one entry
//                    per bird, 1..MAX_DOSES. Only the amount varies here; see
//                    below for why it must.
//   administration   the shared part: administered_at (defaults to now), notes
//   idempotency_key  optional client-generated random key, as on
//                    /api/federfall/intake (federfall-3ty3) — a retried round
//                    replays the stored response instead of double-dosing the
//                    group
//
// ── The amount is PER BIRD, and that is the point ───────────────────────────
// It would be tidier to send one dose and apply it N times, and it would be
// wrong: `dose_rate` is prescribed per KILOGRAM (1700000058), so nine birds on
// one course get nine different amounts. What the group shares is the drug, the
// moment and the decision — never the number in the syringe.
//
// Everything that describes the DRUG is therefore read from the prescription
// server-side (drug, dose_unit, route) rather than accepted from the body: a
// dose row denormalizes those columns (1700000013) so it survives its plan being
// removed, and a client that sent them could make a record disagree with the
// plan it names. What the client sends is only what it alone knows: how much
// went in, and the weight/volume the amount was derived from.
//
// ── Access is checked PER DOSE, and refuses the round ───────────────────────
// Each row resolves its prescription, then its case, and re-states the
// `medication_administrations` create rule — the same restatement exam.pb.js
// makes. A route bypasses collection rules, so it must.
//
// On refusal the WHOLE transaction fails. Skipping the rows it may not write
// would be worse than a refusal here than anywhere else in this codebase: the
// carer has already given the dose, and a screen that says "done" over a bird
// with no row invites a second one.
//
// The refusal cannot name which rows (PocketBase coerces an ApiError's `data`
// into its field-error shape — see vaccinate_batch.pb.js), so the client answers
// custody before the request and this gate is the backstop for a handover
// mid-round.
//
// ── One audit event, not N ──────────────────────────────────────────────────
// `tx.save()` fires no request hooks, so audit_domain.pb.js sees none of these
// rows. `administration.batch_logged` records the round; N identical
// `administration.logged` rows would bury it. Editing one afterwards emits its
// own event as usual.
//
// ── Deliberately NOT here ───────────────────────────────────────────────────
// A route override. The single-dose sheet offers one because an ad-hoc dose may
// legitimately go in another way; a batch follows the plans it names, and nine
// plans may not agree on a route. Any row that needs a different one is logged
// on its own.
//
// And the prescription. This route takes a LIST of plans, never a drug name or a
// carer id: which doses are due is `medication_due`'s answer and the client has
// already resolved it into a round the carer edited. Re-resolving it server-side
// would dose the bird they had just unticked — vaccinate_batch.pb.js' rule.

routerAdd(
  "POST",
  "/api/federfall/administer-batch",
  (e) => {
    // The boundary this route bypasses, stated once for every route that
    // bypasses one — see lib_auth.js.
    const org = require(`${__hooks}/lib_auth.js`).requireMember(e);
    // The gate above checks the caller; the per-case access check and the
    // `administered_by` field below still need their identity.
    const auth = e.auth;

    // NB every helper this handler uses is defined INSIDE it: a hook handler
    // runs in an isolated JSVM context where file-level bindings are out of
    // scope (ReferenceError), which is why the shared parts live in lib_*.js
    // and are require()d here.
    const body = e.requestInfo().body || {};
    const str = (v) => (v === undefined || v === null ? "" : String(v).trim());

    // A dose round, not a herd. High enough for any real group, low enough that
    // a malformed client cannot open a thousand-row transaction.
    const MAX_DOSES = 200;
    // The per-row numbers. All optional: a tablet has no measured amount at all,
    // and only a calculated dose carries the weight it came from.
    const NUMBER_FIELDS = ["dose", "weight_g_used", "volume_ml"];

    const rawDoses = Array.isArray(body.doses) ? body.doses : [];
    if (rawDoses.length === 0) {
      throw new BadRequestError("'doses' must name at least one dose.");
    }
    if (rawDoses.length > MAX_DOSES) {
      throw new BadRequestError("Too many doses in one round.");
    }

    // Deduplicated by prescription: one plan can only be due once, and two
    // identical rows would read as two doses given at the same instant. The
    // FIRST entry wins — a client that sends the same plan twice with different
    // amounts is broken, and picking the later one would silently overwrite
    // what the carer saw at the top of their own list.
    const doses = [];
    const seen = [];
    for (const raw of rawDoses) {
      if (!raw || typeof raw !== "object") {
        throw new BadRequestError("A dose must be an object.");
      }
      const medication = str(raw.medication);
      if (!medication) {
        throw new BadRequestError("Every dose must name its prescription.");
      }
      if (seen.indexOf(medication) !== -1) continue;
      seen.push(medication);

      const numbers = {};
      for (const f of NUMBER_FIELDS) {
        const value = raw[f];
        if (value === undefined || value === null || value === "") continue;
        const n = Number(value);
        if (isNaN(n) || n < 0) {
          throw new BadRequestError(`Invalid ${f}.`);
        }
        numbers[f] = n;
      }
      doses.push({ medication: medication, numbers: numbers });
    }

    const shared =
      body.administration && typeof body.administration === "object"
        ? body.administration
        : {};
    // `administered_at` is required on the collection. Defaulting it to now
    // rather than refusing: a round is given now in every case this route
    // exists for, and a missing timestamp must not lose a dose already given.
    // PB compares "YYYY-MM-DD HH:MM:SS".
    const administeredAt =
      str(shared.administered_at) ||
      new Date().toISOString().replace("T", " ");
    const notes = str(shared.notes);

    // Idempotent replay: a key seen before (per user) means the round already
    // committed — hand back the stored response, dose nothing again.
    const idemKey = str(body.idempotency_key);
    if (idemKey.length > 64) {
      throw new BadRequestError("idempotency_key too long.");
    }
    if (idemKey) {
      let prior = null;
      try {
        prior = e.app.findFirstRecordByFilter(
          "idempotency_keys",
          "endpoint = 'administer_batch' && user = {:u} && key = {:k}",
          { u: auth.id, k: idemKey },
        );
      } catch (_) {
        // no prior request with this key — proceed normally
      }
      if (prior) {
        return e.json(200, prior.get("response"));
      }
    }

    const createdIds = [];
    const caseLabels = [];
    const drugs = [];
    e.app.runInTransaction((tx) => {
      // Mirrors the `medication_administrations` create rule: `case.org =
      // @request.auth.org && (case.active_carer = @request.auth.id ||
      // supervisor || edit-share)`.
      const mayEdit = (caseRec) => {
        if (caseRec.getString("active_carer") === auth.id) return true;
        if (auth.getString("role") === "supervisor") return true;
        const shares = tx.findRecordsByFilter(
          "case_shares",
          "case = {:c} && shared_with = {:u} && access = 'edit'",
          "",
          1,
          0,
          { c: caseRec.id, u: auth.id },
        );
        return shares.length > 0;
      };

      // Resolve and authorise EVERY row before writing any of them, so a
      // refusal costs nothing and reports the whole truth at once rather than
      // whichever row happened to be first.
      const resolved = [];
      const unknown = [];
      const refused = [];
      for (const dose of doses) {
        let plan;
        try {
          plan = tx.findRecordById("medications", dose.medication);
        } catch (_) {
          unknown.push(dose.medication);
          continue;
        }
        if (plan.getString("org") !== org) {
          unknown.push(dose.medication);
          continue;
        }
        let caseRec;
        try {
          caseRec = tx.findRecordById("cases", plan.getString("case"));
        } catch (_) {
          unknown.push(dose.medication);
          continue;
        }
        // A belt-and-braces org check on the case as well: `medications.case`
        // is guarded by org_scope.pb.js, but this route writes a row that hangs
        // off the CASE, so it verifies the thing it is about to write under.
        if (caseRec.getString("org") !== org) {
          unknown.push(dose.medication);
          continue;
        }
        if (!mayEdit(caseRec)) {
          refused.push(dose.medication);
          continue;
        }
        resolved.push({ dose: dose, plan: plan, caseRec: caseRec });
      }
      // No `data` payload on either — see the note at the top: PocketBase
      // rewrites it into a field-error object, so the ids would not survive.
      if (unknown.length > 0) {
        throw new BadRequestError("Unknown prescription.");
      }
      if (refused.length > 0) {
        throw new ForbiddenError("Some of these cases are someone else's.");
      }

      const collection = tx.findCollectionByNameOrId(
        "medication_administrations",
      );
      for (const row of resolved) {
        const plan = row.plan;
        const rec = new Record(collection);
        rec.set("case", row.caseRec.id);
        rec.set("medication", plan.id);
        // Denormalized from the PLAN, never from the body: a dose row must not
        // be able to disagree with the prescription it names.
        rec.set("drug", plan.getString("drug"));
        rec.set("dose_unit", plan.getString("dose_unit"));
        rec.set("route", plan.getString("route"));
        for (const f of NUMBER_FIELDS) {
          if (row.dose.numbers[f] !== undefined) {
            rec.set(f, row.dose.numbers[f]);
          }
        }
        rec.set("administered_at", administeredAt);
        rec.set("notes", notes);
        rec.set("administered_by", auth.id);
        rec.set("org", org);
        tx.save(rec);
        createdIds.push(rec.id);

        const label = row.caseRec.getString("case_number") || row.caseRec.id;
        if (caseLabels.indexOf(label) === -1) caseLabels.push(label);
        const drug = plan.getString("drug");
        if (drug && drugs.indexOf(drug) === -1) drugs.push(drug);
      }

      // One event for the round, with the cases NAMED rather than referenced:
      // an id in an audit row is a bug unless a label sits beside it
      // (federfall-qt96), and these rows may outlive the cases they mention.
      //
      // The subject label is the drug only when the round gave exactly one.
      // Nothing forces a caller to group by drug, and naming the first of
      // several would misreport the round as being about that one.
      require(`${__hooks}/lib_audit.js`).emit(
        e,
        "administration.batch_logged",
        {
          app: tx,
          org: org,
          subject: {
            collection: "medication_administrations",
            id: "",
            label: drugs.length === 1 ? drugs[0] : "",
          },
          detail: {
            doses: resolved.length,
            case_ids: resolved.map((r) => r.caseRec.id),
            case_labels: caseLabels,
            drug_labels: drugs,
            administered_at: administeredAt,
          },
        },
      );

      // Store the response under the idempotency key IN this transaction:
      // either every row committed together with the key, or none did. The
      // unique (endpoint, user, key) index makes a concurrent duplicate roll
      // back whole instead of dosing the group twice.
      if (idemKey) {
        const idem = new Record(tx.findCollectionByNameOrId("idempotency_keys"));
        idem.set("endpoint", "administer_batch");
        idem.set("key", idemKey);
        idem.set("user", auth.id);
        idem.set("response", { created: createdIds.length, ids: createdIds });
        // Retry protection only needs to outlive a retry window; the purge cron
        // in intake.pb.js reaps expired rows for every endpoint.
        idem.set(
          "expires_at",
          new Date(Date.now() + 24 * 3600000).toISOString().replace("T", " "),
        );
        tx.save(idem);
      }
    });

    return e.json(200, { created: createdIds.length, ids: createdIds });
  },
  $apis.requireAuth(),
);
