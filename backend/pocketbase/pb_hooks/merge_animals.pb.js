/// <reference path="../pb_data/types.d.ts" />

// federfall-eqy6 — supervisor animal-merge (duplicate resolution).
//
// REQUIREMENTS.md §6: linking a returning bird at intake is optional and an
// unringed feral is a carer judgment call, so duplicate animal records happen
// in real use. This route folds a `duplicate` animal into a `survivor`: every
// animal-scoped child record (cases, markings, weights, exams, egg_records,
// aviary_stays — every collection with a direct `animal` relation) is
// re-pointed to the survivor,
// the survivor's identity fields are set from whichever record the supervisor
// picked per field, its lifetime_status/current_aviary are re-derived from the
// now-merged case history (same rule as the dispositions reconcile in
// main.pb.js — duplicated here since JSVM handlers don't share file-level
// helpers), and the duplicate is deleted. One transaction: any failure leaves
// both animals exactly as they were.
//
// Request (JSON):
//   survivor    id of the animal record to keep
//   duplicate   id of the animal record to fold in and delete
//   fields      { name, species, sex, photo } — each value is either
//               "survivor" (default) or "duplicate", picking whose value
//               wins on a conflict. Limited to the fields with a real edit
//               surface elsewhere (EditAnimalSheet, AnimalAvatar); is_owned/
//               tags/notes have no UI at all today, so they gap-fill from
//               whichever record has a value instead of surfacing a picker
//               for data nobody can currently see differ. `photo` is a file
//               field, so "duplicate" clones the actual file onto the
//               survivor (`getReuploadableFile` — the documented primitive
//               for copying a file from one record to another) rather than
//               referencing it; "none" clears the survivor's photo.
//
// Supervisor-only end to end: the UI gates the action, the animals delete
// rule already requires a supervisor, and this route re-checks the role
// itself since a custom route bypasses collection API rules entirely.
//
// That role gate also stands in for a custody check here (lib_custody.js,
// federfall-q7ks.5): a supervisor holds every bird in the org by definition, so
// requireCustody would be a literal no-op. If this route is ever widened below
// supervisor, custody has to be added in the same change — a merge rewrites the
// survivor's identity and destroys the duplicate, which makes it the most
// authority-hungry operation in the schema.
routerAdd(
  "POST",
  "/api/federfall/merge-animals",
  (e) => {
    // Supervisor-only, like the deletes this effectively performs
    // (1700000010) — see lib_auth.js.
    const org = require(`${__hooks}/lib_auth.js`).requireSupervisor(e);

    const body = e.requestInfo().body || {};
    const str = (v) => (v === undefined || v === null ? "" : String(v).trim());

    const survivorId = str(body.survivor);
    const duplicateId = str(body.duplicate);
    if (!survivorId || !duplicateId) {
      throw new BadRequestError("'survivor' and 'duplicate' are required.");
    }
    if (survivorId === duplicateId) {
      throw new BadRequestError("An animal cannot be merged with itself.");
    }

    const fieldChoices =
      body.fields && typeof body.fields === "object" ? body.fields : {};

    let result = null;
    e.app.runInTransaction((tx) => {
      let survivor, duplicate;
      try {
        survivor = tx.findRecordById("animals", survivorId);
        duplicate = tx.findRecordById("animals", duplicateId);
      } catch (_) {
        throw new BadRequestError("Unknown animal.");
      }
      if (
        survivor.getString("org") !== org ||
        duplicate.getString("org") !== org
      ) {
        throw new BadRequestError("Unknown animal.");
      }

      // Identity fields with a real edit surface elsewhere (EditAnimalSheet,
      // AnimalAvatar): explicit per-field choice, defaulting to whatever the
      // survivor already has.
      for (const f of ["name", "species", "sex"]) {
        if (fieldChoices[f] === "duplicate") survivor.set(f, duplicate.get(f));
      }

      // Fields with no dedicated UI at all (no screen lets a carer set or
      // even see these today) — gap-fill rather than surfacing a picker for
      // data nobody can currently see differ.
      if (!survivor.getBool("is_owned") && duplicate.getBool("is_owned")) {
        survivor.set("is_owned", true);
      }
      if (!survivor.getString("notes") && duplicate.getString("notes")) {
        survivor.set("notes", duplicate.getString("notes"));
      }
      const survivorTags = survivor.get("tags");
      const hasSurvivorTags = Array.isArray(survivorTags) && survivorTags.length > 0;
      if (!hasSurvivorTags) {
        const duplicateTags = duplicate.get("tags");
        if (Array.isArray(duplicateTags) && duplicateTags.length > 0) {
          survivor.set("tags", duplicateTags);
        }
      }

      // Photo: a file field, so "picking" the duplicate's copy means cloning
      // the blob onto the survivor, not just referencing a filename.
      const photoChoice = fieldChoices.photo;
      if (photoChoice === "duplicate") {
        const name = duplicate.getString("photo");
        if (name) {
          const fs = e.app.newFilesystem();
          try {
            const srcKey = duplicate.baseFilesPath() + "/" + name;
            survivor.set("photo", fs.getReuploadableFile(srcKey, false));
          } finally {
            fs.close();
          }
        }
      } else if (photoChoice === "none") {
        survivor.set("photo", "");
      }

      // The survivor is saved exactly ONCE, at the end — the identity fields
      // above and the derived lifetime state below travel in the same write.
      // Two saves would be two `animals` update events, and a hook that reacts
      // to a field transition sees both of them against the same stale
      // `original()` (the after-success callbacks are deferred to the commit
      // and re-read the same record object), so aviary_stays.pb.js opened two
      // residencies for one move (federfall-0ua6).

      // Re-point every animal-scoped child collection — everything else hangs
      // off `cases`, which is repointed here too, so it follows automatically.
      //
      // federfall-0ua6: this list must name EVERY collection with a direct
      // `animal` relation, because all of them declare `cascadeDelete: true`
      // on it — anything missing here is not "left on the duplicate", it is
      // destroyed by the tx.delete(duplicate) below, without an error and
      // without a trace. `egg_records` (1700000056) and `aviary_stays`
      // (1700000052) both landed after the original four were written and
      // were being erased by every merge. A new collection that points at
      // `animals` has to be added here too; test_rules.py's [animal merge]
      // block is the guard.
      for (const collection of [
        "cases",
        "markings",
        "weights",
        "exams",
        "egg_records",
        "aviary_stays",
      ]) {
        for (const rec of tx.findRecordsByFilter(
          collection,
          "animal = {:a}",
          "",
          0,
          0,
          { a: duplicateId },
        )) {
          rec.set("animal", survivorId);
          // The residency ledger allows exactly ONE open row per animal
          // ("current residency" = the latest row with `ended_at` unset), and
          // the survivor may already have one — so a re-pointed open stay
          // would leave the bird resident in two enclosures at once, which
          // `forAnimalAt` and the aviary rosters both read as truth. Close it
          // as of the merge: the survivor's own residency is re-derived below
          // through `current_aviary`, which aviary_stays.pb.js turns into a
          // fresh open row when it changes. A residency that really continues
          // therefore shows as two consecutive rows split at the merge —
          // honest for an append-only ledger, since the two records WERE
          // separate until this moment.
          if (
            collection === "aviary_stays" &&
            rec.getString("ended_at") === ""
          ) {
            rec.set("ended_at", new Date().toISOString());
          }
          tx.save(rec);
        }
      }

      // Re-derive lifetime_status/current_aviary from the survivor's merged
      // case history — same rule as the dispositions after-update/delete
      // reconcile in main.pb.js: the latest disposition (by `created`) across
      // ALL of the animal's cases now decides its lifetime state.
      const cases = tx.findRecordsByFilter(
        "cases",
        "animal = {:a}",
        "",
        0,
        0,
        { a: survivorId },
      );
      let latest = null;
      for (const c of cases) {
        for (const d of tx.findRecordsByFilter(
          "dispositions",
          "case = {:c}",
          "-created",
          0,
          0,
          { c: c.id },
        )) {
          if (!latest || d.getString("created") > latest.getString("created")) {
            latest = d;
          }
        }
      }
      let lifetime = "in_care";
      let aviary = "";
      if (latest) {
        switch (latest.getString("type")) {
          case "died":
          case "euthanized":
            lifetime = "deceased";
            break;
          case "placed_in_aviary":
            lifetime = "in_aviary";
            aviary = latest.get("aviary");
            break;
          case "released":
          case "returned_to_owner":
          case "transferred":
            lifetime = "at_large_released";
            break;
        }
      } else {
        // No disposition anywhere in the merged history, so nothing has
        // decided this bird's lifetime state — don't let the "in_care"
        // default overwrite a case-less aviary residency. add_animal_sheet
        // .dart adds a resident straight to an enclosure with no case at all
        // (1700000052 lists it as one of the five current_aviary writers), so
        // that residency exists only on the animal record. Keep whichever
        // side documents one, the survivor first: dropping it here would
        // silently evict the bird and close its stay (federfall-0ua6).
        const housed =
          survivor.getString("current_aviary") ||
          duplicate.getString("current_aviary");
        if (housed) {
          lifetime = "in_aviary";
          aviary = housed;
        }
      }
      survivor.set("lifetime_status", lifetime);
      survivor.set("current_aviary", aviary);
      tx.save(survivor);

      // federfall-qt96.4 — emitted BEFORE the delete, while the duplicate can
      // still be described. A merge is destructive and irreversible: the
      // duplicate's id and name are the only trace left of what was absorbed,
      // so they go in `detail` rather than being recoverable from anywhere.
      require(`${__hooks}/lib_audit.js`).emit(e, "animal.merged", {
        app: tx,
        org: org,
        subject: {
          collection: "animals",
          id: survivor.id,
          label: survivor.getString("name") || survivor.getString("species"),
        },
        refs: { animal: survivor.id, duplicate: duplicate.id },
        severity: "notice",
        detail: {
          duplicate_id: duplicate.id,
          duplicate_label:
            duplicate.getString("name") || duplicate.getString("species"),
          // Only the three keys the route acts on — `fields` is raw client
          // input, and an oversized object would fail the row's json size
          // limit and lose the whole event (emit swallows its errors).
          field_choices: {
            name: String(fieldChoices.name || ""),
            species: String(fieldChoices.species || ""),
            sex: String(fieldChoices.sex || ""),
          },
        },
      });

      tx.delete(duplicate);
      result = survivor;
    });

    return e.json(200, { id: result.id });
  },
  $apis.requireAuth(),
);
