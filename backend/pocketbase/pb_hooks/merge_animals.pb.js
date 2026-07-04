/// <reference path="../pb_data/types.d.ts" />

// federfall-eqy6 — supervisor animal-merge (duplicate resolution).
//
// REQUIREMENTS.md §6: linking a returning bird at intake is optional and an
// unringed feral is a carer judgment call, so duplicate animal records happen
// in real use. This route folds a `duplicate` animal into a `survivor`: every
// animal-scoped child record (cases, markings, weights, exams — the four
// collections with a direct `animal` relation) is re-pointed to the survivor,
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
routerAdd(
  "POST",
  "/api/federfall/merge-animals",
  (e) => {
    const auth = e.auth;
    if (
      !auth ||
      !auth.getBool("is_active") ||
      auth.getString("role") !== "supervisor"
    ) {
      throw new ForbiddenError("Not allowed.");
    }
    const org = auth.getString("org");
    if (!org) {
      throw new ForbiddenError("No organisation.");
    }

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

      tx.save(survivor);

      // Re-point every animal-scoped child collection (the four with a
      // direct `animal` relation) — everything else hangs off `cases`, which
      // is repointed here too, so it follows automatically.
      for (const collection of ["cases", "markings", "weights", "exams"]) {
        for (const rec of tx.findRecordsByFilter(
          collection,
          "animal = {:a}",
          "",
          0,
          0,
          { a: duplicateId },
        )) {
          rec.set("animal", survivorId);
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
      }
      survivor.set("lifetime_status", lifetime);
      survivor.set("current_aviary", aviary);
      tx.save(survivor);

      tx.delete(duplicate);
      result = survivor;
    });

    return e.json(200, { id: result.id });
  },
  $apis.requireAuth(),
);
