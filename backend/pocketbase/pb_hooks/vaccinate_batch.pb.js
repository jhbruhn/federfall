/// <reference path="../pb_data/types.d.ts" />

// federfall-s63u — vaccinate a whole enclosure in one act.
//
// Vaccinating a flock is ONE decision, not N: the same product, the same
// Charge, the same day, minus whichever birds are skipped. Recording it as N
// separate saves from the client is what exam.pb.js and microscopy.pb.js exist
// to stop (federfall-lov0) — this app is online-only, so a connection lost
// halfway leaves a flock half-recorded, and nothing afterwards can say which
// half. Worse than for those two: the missing rows are indistinguishable from
// birds that were deliberately skipped, so the error is silent AND permanent.
//
// So: one transaction, all rows or none.
//
// Request (JSON):
//
//   animals          [animal id] — the birds to vaccinate. 1..MAX_ANIMALS.
//   vaccination      the shared row: vaccine (required), target,
//                    administered_at, batch, dose, dose_unit, route, series,
//                    next_due_at, vet, notes
//   idempotency_key  optional client-generated random key, as on
//                    /api/federfall/intake (federfall-3ty3) — a retried batch
//                    replays the stored response instead of vaccinating the
//                    flock twice
//
// `animal`, `author` and `org` are never taken from the body: the first is the
// list, the other two come from the authenticated user.
//
// ── Custody is checked PER ANIMAL, and refuses the batch ────────────────────
// An enclosure's roster can contain a bird whose open case belongs to another
// carer — the collection rules would refuse exactly those rows. This route
// bypasses collection rules (that is what a route does), so it re-states the
// check itself through lib_custody.js, and on refusal it fails the WHOLE
// transaction rather than skipping the birds it may not write.
//
// Skipping would be the friendlier-looking choice and the wrong one: the keeper
// walks away believing the flock is done, and the one bird that was somebody
// else's is the one with no record.
//
// The refusal cannot say WHICH birds, and that is not for want of trying:
// PocketBase coerces an ApiError's `data` into its field-error shape, so
// `{animals: [id, ...]}` arrives as `{animals: {code: "validation_invalid_value",
// message: "Invalid value."}}` — verified against 0.39.8. Naming them in the
// message instead would put server-authored prose (and a list of ids) in front
// of the user in whatever language this file happens to be written in. So the
// answer belongs on the client, BEFORE the request: `canWriteAnimal` already
// answers custody per bird, so the batch sheet marks the ones it cannot write
// and leaves them out. This gate is the backstop for the race — a bird handed
// over between opening the sheet and confirming it — not the everyday path.
//
// ── One audit event, not N ──────────────────────────────────────────────────
// `tx.save()` fires no request hooks, so audit_domain.pb.js sees none of these
// rows — the same as every other route here. That is deliberate rather than a
// gap: `vaccination.batch_recorded` records the act that actually happened, and
// N identical `vaccination.created` rows would bury it. The individual rows are
// ordinary records afterwards; editing one emits its own event as usual.
//
// ── Deliberately NOT here ───────────────────────────────────────────────────
// Attachments. A vial-label photo would have to be stored once per row, which
// is N copies of one file for no gain; it is added afterwards on whichever
// animal's record should carry it. The route is therefore plain JSON, not the
// multipart `@jsonPayload` shape intake and microscopy use.
//
// And the enclosure. This route takes a LIST of animals, never an aviary id:
// which birds live where is `aviary_stays`' answer (1700000052) and the client
// has already resolved it to a roster the keeper edited. Resolving it again
// server-side would vaccinate a bird the keeper had just deselected.

routerAdd(
  "POST",
  "/api/federfall/vaccinate-batch",
  (e) => {
    // The boundary this route bypasses, stated once for every route that
    // bypasses one — see lib_auth.js.
    const org = require(`${__hooks}/lib_auth.js`).requireMember(e);
    const auth = e.auth;

    // NB every helper this handler uses is defined INSIDE it: a hook handler
    // runs in an isolated JSVM context where file-level bindings are out of
    // scope (ReferenceError), which is why the shared parts live in lib_*.js
    // and are require()d here.
    const body = e.requestInfo().body || {};
    const str = (v) => (v === undefined || v === null ? "" : String(v).trim());

    // A flock, not a herd. High enough for any real enclosure, low enough that
    // a malformed client cannot open a thousand-row transaction.
    const MAX_ANIMALS = 200;
    const SERIES = ["primary", "booster"];
    // The shared fields, mirroring 1700000087. `animal`, `author` and `org` are
    // deliberately absent — they are not the client's to send.
    const TEXT_FIELDS = [
      "vaccine",
      "target",
      "batch",
      "dose_unit",
      "vet",
      "notes",
    ];
    const DATE_FIELDS = ["administered_at", "next_due_at"];

    const rawAnimals = Array.isArray(body.animals) ? body.animals : [];
    // Deduplicated: a client that sends the same bird twice means it once, and
    // two identical rows on one animal is not a record anybody can read.
    const animalIds = [];
    for (const raw of rawAnimals) {
      const id = str(raw);
      if (id && animalIds.indexOf(id) === -1) animalIds.push(id);
    }
    if (animalIds.length === 0) {
      throw new BadRequestError("'animals' must name at least one animal.");
    }
    if (animalIds.length > MAX_ANIMALS) {
      throw new BadRequestError("Too many animals in one batch.");
    }

    const shared =
      body.vaccination && typeof body.vaccination === "object"
        ? body.vaccination
        : {};
    const vaccine = str(shared.vaccine);
    if (!vaccine) {
      throw new BadRequestError("'vaccination.vaccine' is required.");
    }
    const series = str(shared.series);
    if (series && SERIES.indexOf(series) === -1) {
      throw new BadRequestError("Unknown series.");
    }
    const dose =
      shared.dose === undefined || shared.dose === null || shared.dose === ""
        ? null
        : Number(shared.dose);
    if (dose !== null && (isNaN(dose) || dose < 0)) {
      throw new BadRequestError("Invalid dose.");
    }
    const routeId = str(shared.route);

    // Idempotent replay: a key seen before (per user) means the batch already
    // committed — hand back the stored response, vaccinate nothing again.
    const idemKey = str(body.idempotency_key);
    if (idemKey.length > 64) {
      throw new BadRequestError("idempotency_key too long.");
    }
    if (idemKey) {
      let prior = null;
      try {
        prior = e.app.findFirstRecordByFilter(
          "idempotency_keys",
          "endpoint = 'vaccinate_batch' && user = {:u} && key = {:k}",
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
      const custody = require(`${__hooks}/lib_custody.js`);

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

      // Resolve and authorise EVERY bird before writing any row, so a refusal
      // costs nothing and reports the whole truth at once rather than whichever
      // bird happened to be first.
      const animals = [];
      const unknown = [];
      const refused = [];
      for (const id of animalIds) {
        let animal;
        try {
          animal = tx.findRecordById("animals", id);
        } catch (_) {
          unknown.push(id);
          continue;
        }
        if (animal.getString("org") !== org) {
          unknown.push(id);
          continue;
        }
        if (!custody.holds(tx, auth, id)) {
          refused.push(id);
          continue;
        }
        animals.push(animal);
      }
      // No `data` payload on either — see the note at the top: PocketBase
      // rewrites it into a field-error object, so the ids would not survive.
      if (unknown.length > 0) {
        throw new BadRequestError("Unknown animal.");
      }
      if (refused.length > 0) {
        throw new ForbiddenError(
          "Some of these animals are in someone else's care.",
        );
      }

      const collection = tx.findCollectionByNameOrId("vaccinations");
      for (const animal of animals) {
        const rec = new Record(collection);
        rec.set("animal", animal.id);
        for (const f of TEXT_FIELDS) rec.set(f, str(shared[f]));
        for (const f of DATE_FIELDS) rec.set(f, str(shared[f]));
        rec.set("series", series);
        rec.set("route", routeId);
        if (dose !== null) rec.set("dose", dose);
        rec.set("author", auth.id);
        rec.set("org", org);
        tx.save(rec);
        createdIds.push(rec.id);
      }

      // One event for the act, with the animals NAMED rather than referenced:
      // an id in an audit row is a bug unless a label sits beside it
      // (federfall-qt96), and these rows may outlive the birds they mention.
      const names = [];
      for (const animal of animals) {
        names.push(
          animal.getString("name") || animal.getString("species") || "",
        );
      }
      require(`${__hooks}/lib_audit.js`).emit(e, "vaccination.batch_recorded", {
        app: tx,
        org: org,
        subject: { collection: "vaccinations", id: "", label: vaccine },
        detail: {
          animals: animals.length,
          animal_ids: animals.map((a) => a.id),
          animal_labels: names,
          vaccine: vaccine,
          target: str(shared.target),
          batch: str(shared.batch),
          administered_at: str(shared.administered_at),
          next_due_at: str(shared.next_due_at),
          series: series,
        },
      });

      // Store the response under the idempotency key IN this transaction:
      // either every row committed together with the key, or none did. The
      // unique (endpoint, user, key) index makes a concurrent duplicate roll
      // back whole instead of vaccinating the flock twice.
      if (idemKey) {
        const idem = new Record(tx.findCollectionByNameOrId("idempotency_keys"));
        idem.set("endpoint", "vaccinate_batch");
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
