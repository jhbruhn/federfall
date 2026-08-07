/// <reference path="../pb_data/types.d.ts" />

// federfall-zod — atomic case intake.
//
// The intake wizard used to create animal → finder → case as three client
// calls; a failure mid-sequence stranded an orphaned animal and — worse — a
// finder PII record the creating carer could not even see (the finders list
// rule only grants visibility through a linked case), and retrying the form
// created duplicates. This route creates everything in ONE server-side
// transaction: any failure rolls the whole intake back.
//
// It is also the ONLY writer of `cases.finder`: migration 1700000044 locks the
// field against direct client writes (`@request.body.finder:isset = false` on
// the cases create/update rules), which closes the re-point/enumeration hole
// of federfall-9hy — a client can no longer link an arbitrary existing finder
// to a case by id.
//
// Request (JSON, or multipart with `@jsonPayload` + `intake_photos` files):
//   animal           existing animal id (re-identification) — XOR `species`
//   species, name    new animal identity
//   finder           {first_name,last_name,phone,email,city} — all optional;
//                    a finder record is only created when a field is filled
//   case             intake fields (whitelisted below)
//   weight_g         optional intake weight → a `weights` timeline row
//   quarantine_days  optional override → a `quarantine_records` row replacing
//                    the org-default one the cases hook would create
//   idempotency_key  optional client-generated random key (federfall-3ty3):
//                    the response is stored under (intake, user, key) in the
//                    SAME transaction, and a replay of the key — e.g. a retry
//                    after a timeout whose first request actually committed —
//                    returns the stored response instead of creating a second
//                    animal+case. See 1700000050_intake_idempotency.js.
//
// org and active_carer always come from the authenticated user (mirroring the
// cases createRule `active_carer = @request.auth.id`); the case_number/status
// hook in main.pb.js runs inside the same transaction.
routerAdd(
  "POST",
  "/api/federfall/intake",
  (e) => {
    // Mirrors the collection rules this route bypasses: active member of an
    // org, and not a guest (guests are walled off from all data). One
    // implementation for every route — see lib_auth.js.
    const org = require(`${__hooks}/lib_auth.js`).requireMember(e);
    // The gate above checks the caller; the writes below still need their
    // identity (active_carer, author, set_by, the idempotency key's owner).
    const auth = e.auth;

    const body = e.requestInfo().body || {};
    const str = (v) => (v === undefined || v === null ? "" : String(v).trim());

    let photos = [];
    try {
      photos = e.findUploadedFiles("intake_photos") || [];
    } catch (_) {
      // Not multipart / no files staged.
    }

    const animalId = str(body.animal);
    const species = str(body.species);
    if (!animalId && !species) {
      throw new BadRequestError("Either 'animal' or 'species' is required.");
    }

    // Idempotent replay: a key seen before (per user) means the intake already
    // committed — hand back the stored response, write nothing.
    const idemKey = str(body.idempotency_key);
    if (idemKey.length > 64) {
      throw new BadRequestError("idempotency_key too long.");
    }
    if (idemKey) {
      let prior = null;
      try {
        prior = e.app.findFirstRecordByFilter(
          "idempotency_keys",
          "endpoint = 'intake' && user = {:u} && key = {:k}",
          { u: auth.id, k: idemKey },
        );
      } catch (_) {
        // no prior request with this key — proceed normally
      }
      if (prior) {
        return e.json(200, prior.get("response"));
      }
    }

    const caseData =
      body.case && typeof body.case === "object" ? body.case : {};
    const finderData =
      body.finder && typeof body.finder === "object" ? body.finder : null;

    let created = null;
    e.app.runInTransaction((tx) => {
      // Animal: reuse (re-identified return, must be same-org) or create.
      let animal;
      if (animalId) {
        try {
          animal = tx.findRecordById("animals", animalId);
        } catch (_) {
          throw new BadRequestError("Unknown animal.");
        }
        if (animal.getString("org") !== org) {
          throw new BadRequestError("Unknown animal.");
        }
      } else {
        animal = new Record(tx.findCollectionByNameOrId("animals"));
        animal.set("species", species);
        if (str(body.name)) animal.set("name", str(body.name));
        animal.set("org", org);
        tx.save(animal);
      }
      const aId = animal.id;

      // Finder (PII): only when at least one contact field is filled.
      let finderId = "";
      if (finderData) {
        const filled = ["first_name", "last_name", "phone", "email", "city"]
          .filter((f) => str(finderData[f]));
        if (filled.length > 0) {
          const finder = new Record(tx.findCollectionByNameOrId("finders"));
          for (const f of filled) finder.set(f, str(finderData[f]));
          finder.set("org", org);
          tx.save(finder);
          finderId = finder.id;
        }
      }

      // Case: whitelisted intake fields; identity/scope set server-side.
      const rec = new Record(tx.findCollectionByNameOrId("cases"));
      rec.set("animal", aId);
      rec.set("org", org);
      rec.set("active_carer", auth.id);
      if (finderId) rec.set("finder", finderId);
      const FIELDS = [
        "admission_reasons", "age_class", "found_at", "admitted_at",
        "find_location", "find_geo", "city", "region", "intake_notes",
      ];
      for (const f of FIELDS) {
        if (caseData[f] !== undefined && caseData[f] !== null) {
          rec.set(f, caseData[f]);
        }
      }
      if (photos.length > 0) rec.set("intake_photos", photos);
      tx.save(rec); // case_number/status hook runs in this transaction
      created = rec;

      // federfall-v1yh — promote the first intake photo to the bird's
      // portrait when it has none. `animals.photo` is org-wide readable
      // identity data while `cases.intake_photos` is case-scoped, so the
      // header avatar used to exist only for people on the case — worst for
      // the carer holding a bird they have no case for yet, who is exactly
      // who the org-wide identity layer is for. This deliberately widens ONE
      // clinical photo per bird to the whole org (an intake shot can carry
      // the finder's hands/home, whose PII is otherwise case-gated); the
      // wizard nudges for a bird-only portrait and anyone can swap the
      // picture afterwards. Only ever fills an EMPTY field: a portrait a user
      // chose — or one an earlier intake promoted — is never overwritten.
      //
      // The same uploaded File is saved onto two records. PocketBase keys
      // blobs as `<collectionId>/<recordId>/<name>` and re-opens the
      // multipart reader per upload, so each record gets its own copy and
      // deleting one leaves the other's file intact. Both fields carry the
      // same maxSize/mimeTypes (1700000017 / 1700000048), so a file the case
      // accepted cannot fail validation here and abort the intake.
      if (photos.length > 0 && !animal.getString("photo")) {
        animal.set("photo", photos[0]);
        tx.save(animal);
      }

      // Intake weight: a real weights row (single source of truth + trend),
      // baselined at admission — was a separate client call before.
      // parseFloat, not parseInt (federfall-nd2c): `weights.weight_g` is a
      // plain number column with no integer constraint and the exam route
      // writes fractions into it, so a scale reading of 180.5 g must survive
      // an intake the same way it survives an examination.
      const weight = parseFloat(body.weight_g);
      if (!isNaN(weight) && weight > 0) {
        const w = new Record(tx.findCollectionByNameOrId("weights"));
        w.set("animal", aId);
        w.set("case", rec.id);
        w.set("weight_g", weight);
        const measured = str(caseData.admitted_at);
        w.set("measured_at", measured || new Date().toISOString());
        w.set("author", auth.id);
        w.set("org", org);
        tx.save(w);
      }

      // Quarantine override: creating the row here (in-tx) makes the
      // after-create default hook in main.pb.js skip its org-default row
      // (it is idempotent), so a per-case duration is atomic too.
      const days = parseInt(body.quarantine_days, 10);
      if (!isNaN(days) && days > 0) {
        const baseStr = str(caseData.admitted_at);
        const base = baseStr ? new Date(baseStr.replace(" ", "T")) : new Date();
        const q = new Record(
          tx.findCollectionByNameOrId("quarantine_records"),
        );
        q.set("case", rec.id);
        q.set("set_at", base.toISOString());
        q.set(
          "quarantine_until",
          new Date(base.getTime() + days * 86400000).toISOString(),
        );
        q.set("set_by", auth.id);
        q.set("org", org);
        tx.save(q);
      }

      // Store the response under the idempotency key IN this transaction:
      // either everything above committed together with the key, or nothing
      // did. The unique (endpoint, user, key) index makes a concurrent
      // duplicate roll back whole instead of double-creating.
      if (idemKey) {
        const idem = new Record(tx.findCollectionByNameOrId("idempotency_keys"));
        idem.set("endpoint", "intake");
        idem.set("key", idemKey);
        idem.set("user", auth.id);
        idem.set("response", {
          id: rec.id,
          animal: rec.getString("animal"),
          case_number: rec.getString("case_number"),
        });
        // Retry protection only needs to outlive a retry window; the purge
        // cron below reaps expired rows. PB compares "YYYY-MM-DD HH:MM:SS".
        idem.set(
          "expires_at",
          new Date(Date.now() + 24 * 3600000).toISOString().replace("T", " "),
        );
        tx.save(idem);
      }

      // federfall-qt96.4 — ONE event for the whole intake. This route never
      // fires request hooks (everything above is tx.save), and even if it did,
      // five `*.created` rows would describe a bird being admitted worse than
      // one line does. Emitted with the transaction app, so the log entry
      // commits with the records it describes or not at all.
      require(`${__hooks}/lib_audit.js`).emit(e, "case.intake", {
        app: tx,
        org: org,
        subject: {
          collection: "cases",
          id: rec.id,
          label: rec.getString("case_number"),
        },
        caseId: rec.id,
        caseLabel: rec.getString("case_number"),
        refs: finderId ? { animal: aId, finder: finderId } : { animal: aId },
        detail: {
          species: animal.getString("species"),
          // Whether this was a re-identified returner or a new bird is the
          // most interesting thing about an intake after the species.
          reidentified: !!animalId,
          // The finder is referenced by id in `refs` and never described.
          has_finder: !!finderId,
          intake_photos: photos.length,
        },
      });
    });

    return e.json(200, {
      id: created.id,
      animal: created.getString("animal"),
      case_number: created.getString("case_number"),
    });
  },
  $apis.requireAuth(),
);

// federfall-3ty3 — reap expired idempotency keys daily (same pattern as the
// geocode cache purge). The handler runs in its own JSVM context.
cronAdd("idempotencyKeyPurge", "30 4 * * *", () => {
  const PAGE = 500;
  const now = new Date().toISOString().replace("T", " ");
  let purged = 0;
  let offset = 0;
  // Re-query from the same offset each round: deleting shrinks the result set.
  //
  // federfall-ex20 — a row whose delete keeps failing does NOT leave the filter,
  // so with a fixed offset of 0 a full page of persistently failing rows refills
  // the batch forever and `batch.length < PAGE` never becomes true. Advancing
  // past a page that removed nothing steps over them — the same guard
  // finder_retention.pb.js uses.
  for (;;) {
    let batch;
    try {
      batch = $app.findRecordsByFilter(
        "idempotency_keys",
        "expires_at < {:now}",
        "expires_at",
        PAGE,
        offset,
        { now: now },
      );
    } catch (_) {
      break;
    }
    if (!batch || batch.length === 0) break;
    let purgedThisBatch = 0;
    for (let i = 0; i < batch.length; i++) {
      try {
        $app.delete(batch[i]);
        purged++;
        purgedThisBatch++;
      } catch (_) {
        // skip a row already gone / locked; the next run retries it
      }
    }
    if (purgedThisBatch === 0) offset += batch.length;
    if (batch.length < PAGE) break;
  }
  if (purged > 0) {
    $app.logger().info("idempotency key purge", "removed", purged);
  }
});
