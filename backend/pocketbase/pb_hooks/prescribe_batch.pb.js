/// <reference path="../pb_data/types.d.ts" />

// federfall-hqhg — prescribe one course to a whole group of cases in one act.
//
// Nine pigeons on the same antiparasitic is ONE decision by one vet, and
// entering it nine times is nine chances to mistype an interval. So the form
// asks once and this route writes the rows — the same shape
// vaccinate_batch.pb.js gives a flock (federfall-s63u), for the same reason
// exam.pb.js and microscopy.pb.js exist (federfall-lov0): this app is
// online-only, and a connection lost halfway through N client-side saves leaves
// a course half prescribed with nothing afterwards able to say which half.
//
// Sharper here than for a vaccination, because a prescription is not a record
// of something that already happened but an instruction for what happens next:
// the birds whose row is missing are indistinguishable from the birds somebody
// deliberately left off the course, and they simply never come up on the
// worklist. A silent omission is a bird that does not get treated.
//
// So: one transaction, all rows or none.
//
// Request (JSON):
//
//   cases            [case id] — the cases to prescribe for. 1..MAX_CASES.
//   medication       the shared plan: drug (required), dose, dose_unit,
//                    dose_rate, concentration_per_ml, frequency_kind,
//                    interval_hours, cycle_on_days, cycle_off_days, route,
//                    started_at, ended_at, is_controlled, instructions,
//                    prescribed_by
//   idempotency_key  optional client-generated random key, as on
//                    /api/federfall/intake (federfall-3ty3) — a retried batch
//                    replays the stored response instead of prescribing the
//                    course twice
//
// `case` and `org` are never taken from the plan: the first is the list, the
// second comes from the authenticated caller. `medications` has no author field
// (lib_authorship.js) — a prescription names its prescriber in `prescribed_by`,
// which is free text about an outside vet, not the person typing.
//
// ── Why N rows and not one shared row ───────────────────────────────────────
// The obvious-looking alternative is a "group" or "cohort" that nine cases
// point at, so the plan exists once. It is wrong by the third day:
//
//   • `dose_rate` is per kilogram, so the nine birds do not even get the same
//     amount — what is shared is the decision, never the dose.
//   • `medication_due` joins `medications.case → cases.active_carer`; a row
//     belonging to nine cases has nine carers and therefore none.
//   • the access rules on `medications` resolve through `case`, so a shared row
//     has no single answer to "may I read this".
//   • the moment ONE bird comes off the course — released, died, reacted badly
//     — the group has to be split, and that is the ordinary case, not the edge.
//
// Each bird keeps its own row, editable and endable on its own. This route is a
// shortcut for writing them, and deliberately nothing else: there is no batch
// EDIT and no batch END, because those are exactly the moments the birds start
// to differ. Once written, a row here is an ordinary prescription.
//
// ── Access is checked PER CASE, and refuses the batch ───────────────────────
// A route bypasses collection rules, so it restates the `medications` create
// rule itself — the same restatement exam.pb.js makes, and deliberately NOT an
// animal-custody check (lib_custody.js): a prescription is a case timeline
// record, and requiring custody of the bird would refuse a carer writing up the
// course for their own case.
//
// On refusal the WHOLE transaction fails rather than skipping the cases it may
// not write. Skipping is the friendlier-looking choice and the wrong one: the
// carer walks away believing the group is on the course, and the one bird that
// was somebody else's is the one bird with no plan.
//
// The refusal cannot name which cases: PocketBase coerces an ApiError's `data`
// into its field-error shape, so `{cases: [id, ...]}` arrives as a single
// `{code, message}` pair (verified against 0.39.8, see vaccinate_batch.pb.js).
// The answer therefore belongs on the client BEFORE the request — the picker
// offers only cases the caller carries — and this gate is the backstop for the
// race, a case handed over between opening the sheet and confirming it.
//
// ── One audit event, not N ──────────────────────────────────────────────────
// `tx.save()` fires no request hooks, so audit_domain.pb.js sees none of these
// rows. That is deliberate, as in every route here: `medication.batch_prescribed`
// records the act that happened, and N identical `medication.prescribed` rows
// would bury it. Editing one afterwards emits its own event as usual.

routerAdd(
  "POST",
  "/api/federfall/prescribe-batch",
  (e) => {
    // The boundary this route bypasses, stated once for every route that
    // bypasses one — see lib_auth.js.
    const org = require(`${__hooks}/lib_auth.js`).requireMember(e);
    // The gate above checks the caller; the per-case access check below still
    // needs their identity and role.
    const auth = e.auth;

    // NB every helper this handler uses is defined INSIDE it: a hook handler
    // runs in an isolated JSVM context where file-level bindings are out of
    // scope (ReferenceError), which is why the shared parts live in lib_*.js
    // and are require()d here.
    const body = e.requestInfo().body || {};
    const str = (v) => (v === undefined || v === null ? "" : String(v).trim());

    // A group, not a herd. High enough for any real course, low enough that a
    // malformed client cannot open a thousand-row transaction.
    const MAX_CASES = 200;
    const FREQUENCY_KINDS = ["once", "scheduled", "as_needed"];
    // The shared fields, mirroring what the prescription form writes through
    // the collection API. `case` and `org` are deliberately absent — they are
    // not the client's to send.
    const TEXT_FIELDS = ["drug", "dose_unit", "instructions", "prescribed_by"];
    const DATE_FIELDS = ["started_at", "ended_at"];
    // Optional numbers: absent/empty leaves the column unset rather than
    // storing 0, which for a dose or an interval would be a different plan.
    const NUMBER_FIELDS = [
      "dose",
      "dose_rate",
      "concentration_per_ml",
      "interval_hours",
    ];

    const rawCases = Array.isArray(body.cases) ? body.cases : [];
    // Deduplicated: a client that sends the same case twice means it once, and
    // two identical plans on one case is not a prescription anybody can follow
    // — the worklist would show the dose due twice.
    const caseIds = [];
    for (const raw of rawCases) {
      const id = str(raw);
      if (id && caseIds.indexOf(id) === -1) caseIds.push(id);
    }
    if (caseIds.length === 0) {
      throw new BadRequestError("'cases' must name at least one case.");
    }
    if (caseIds.length > MAX_CASES) {
      throw new BadRequestError("Too many cases in one batch.");
    }

    const shared =
      body.medication && typeof body.medication === "object"
        ? body.medication
        : {};
    const drug = str(shared.drug);
    if (!drug) {
      throw new BadRequestError("'medication.drug' is required.");
    }
    const frequencyKind = str(shared.frequency_kind);
    if (frequencyKind && FREQUENCY_KINDS.indexOf(frequencyKind) === -1) {
      throw new BadRequestError("Unknown frequency kind.");
    }

    const numbers = {};
    for (const f of NUMBER_FIELDS) {
      const raw = shared[f];
      if (raw === undefined || raw === null || raw === "") continue;
      const n = Number(raw);
      if (isNaN(n) || n < 0) {
        throw new BadRequestError(`Invalid ${f}.`);
      }
      numbers[f] = n;
    }

    // Half a rhythm is no rhythm — the exact reading `medication_due` takes of
    // the stored pair (1700000090), restated here so the two cannot disagree
    // about a plan this route wrote. An incomplete or non-positive pair is
    // dropped rather than refused: it means "no cycle", which is a plan.
    const cycleOn = parseInt(str(shared.cycle_on_days), 10);
    const cycleOff = parseInt(str(shared.cycle_off_days), 10);
    const hasCycle =
      !isNaN(cycleOn) && !isNaN(cycleOff) && cycleOn > 0 && cycleOff > 0;

    const routeId = str(shared.route);
    const controlled = shared.is_controlled === true;

    // Idempotent replay: a key seen before (per user) means the batch already
    // committed — hand back the stored response, prescribe nothing again.
    const idemKey = str(body.idempotency_key);
    if (idemKey.length > 64) {
      throw new BadRequestError("idempotency_key too long.");
    }
    if (idemKey) {
      let prior = null;
      try {
        prior = e.app.findFirstRecordByFilter(
          "idempotency_keys",
          "endpoint = 'prescribe_batch' && user = {:u} && key = {:k}",
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
    e.app.runInTransaction((tx) => {
      // A route may name a route only from the caller's own org — the same
      // check org_scope.pb.js makes for a rule-driven write.
      if (routeId) {
        let route;
        try {
          route = tx.findRecordById("medication_routes", routeId);
        } catch (_) {
          throw new BadRequestError("Unknown route.");
        }
        if (route.getString("org") !== org) {
          throw new BadRequestError("Unknown route.");
        }
      }

      // Mirrors the `medications` create rule: `case.org = @request.auth.org &&
      // (case.active_carer = @request.auth.id || supervisor || edit-share)`.
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

      // Resolve and authorise EVERY case before writing any row, so a refusal
      // costs nothing and reports the whole truth at once rather than whichever
      // case happened to be first.
      const cases = [];
      const unknown = [];
      const refused = [];
      for (const id of caseIds) {
        let caseRec;
        try {
          caseRec = tx.findRecordById("cases", id);
        } catch (_) {
          unknown.push(id);
          continue;
        }
        if (caseRec.getString("org") !== org) {
          unknown.push(id);
          continue;
        }
        if (!mayEdit(caseRec)) {
          refused.push(id);
          continue;
        }
        cases.push(caseRec);
      }
      // No `data` payload on either — see the note at the top: PocketBase
      // rewrites it into a field-error object, so the ids would not survive.
      if (unknown.length > 0) {
        throw new BadRequestError("Unknown case.");
      }
      if (refused.length > 0) {
        throw new ForbiddenError("Some of these cases are someone else's.");
      }

      const collection = tx.findCollectionByNameOrId("medications");
      for (const caseRec of cases) {
        const rec = new Record(collection);
        rec.set("case", caseRec.id);
        for (const f of TEXT_FIELDS) rec.set(f, str(shared[f]));
        for (const f of DATE_FIELDS) rec.set(f, str(shared[f]));
        for (const f of NUMBER_FIELDS) {
          if (numbers[f] !== undefined) rec.set(f, numbers[f]);
        }
        rec.set("frequency_kind", frequencyKind);
        if (hasCycle) {
          rec.set("cycle_on_days", cycleOn);
          rec.set("cycle_off_days", cycleOff);
        }
        rec.set("route", routeId);
        rec.set("is_controlled", controlled);
        rec.set("org", org);
        tx.save(rec);
        createdIds.push(rec.id);
      }

      // One event for the act, with the cases NAMED rather than referenced: an
      // id in an audit row is a bug unless a label sits beside it
      // (federfall-qt96), and these rows may outlive the cases they mention.
      const labels = [];
      for (const caseRec of cases) {
        labels.push(caseRec.getString("case_number") || caseRec.id);
      }
      require(`${__hooks}/lib_audit.js`).emit(e, "medication.batch_prescribed", {
        app: tx,
        org: org,
        subject: { collection: "medications", id: "", label: drug },
        detail: {
          cases: cases.length,
          case_ids: cases.map((c) => c.id),
          case_labels: labels,
          drug: drug,
          dose: numbers.dose === undefined ? "" : numbers.dose,
          dose_rate: numbers.dose_rate === undefined ? "" : numbers.dose_rate,
          dose_unit: str(shared.dose_unit),
          frequency_kind: frequencyKind,
          interval_hours:
            numbers.interval_hours === undefined ? "" : numbers.interval_hours,
          cycle_on_days: hasCycle ? cycleOn : "",
          cycle_off_days: hasCycle ? cycleOff : "",
          started_at: str(shared.started_at),
          ended_at: str(shared.ended_at),
        },
      });

      // Store the response under the idempotency key IN this transaction:
      // either every row committed together with the key, or none did. The
      // unique (endpoint, user, key) index makes a concurrent duplicate roll
      // back whole instead of prescribing the course twice.
      if (idemKey) {
        const idem = new Record(tx.findCollectionByNameOrId("idempotency_keys"));
        idem.set("endpoint", "prescribe_batch");
        idem.set("key", idemKey);
        idem.set("user", auth.id);
        idem.set("response", { created: createdIds.length, ids: createdIds });
        // Retry protection only needs to outlive a retry window; the purge cron
        // in intake.pb.js reaps expired rows for every endpoint. PB compares
        // "YYYY-MM-DD HH:MM:SS".
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
