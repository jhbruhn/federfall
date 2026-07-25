/// <reference path="../pb_data/types.d.ts" />

// federfall-ti77 — a record's `animal` must live in the record's own org.
//
// Every collection that points at `animals` is org-scoped through its own `org`
// (or, for exams, its parent case), but nothing checked that the ANIMAL it names
// belongs to that same org. The identity-layer collections are org-wide writable
// (5yg.4) and 1700000043 deliberately exempts their `animal` from the
// `@request.body.<field>:isset = false` guards, reasoning that a re-point
// "grants the writer nothing they don't already have org-wide". True within an
// org — but the field was equally free to name another org's bird:
//
//     PATCH /api/collections/weights/records/<id>  {"animal": "<foreign animal>"}
//
// `org = @request.auth.org` still passes (the row's own org is untouched, and
// `org` does carry the isset guard), so the write succeeded. The row stayed
// unreadable to that org, but it hung off their animal — and `cascadeDelete` on
// `animal` means deleting that bird destroyed another org's clinical history.
//
// A rule cannot fix this: plain field references in an UPDATE rule are evaluated
// against the STORED record — 1700000043's own finding — so
// `animal.org = @request.auth.org` would check the OLD animal and ignore the
// incoming one. Hence a hook, the way intake.pb.js / exam.pb.js / main.pb.js
// validate their other referenced records.
//
// Covers create as well as update so the invariant holds for every writer,
// including hook-internal `app.save()` calls (merge_animals.pb.js re-points
// cases and markings at the surviving animal — same org, so it passes).
//
// `aviary_stays` is deliberately absent: it has no client write path at all
// (create/update/delete rules are null, 1700000052) and its rows are built by a
// hook from the animals record itself, so the animal and org cannot disagree.
//
// JSVM gotcha: each callback runs in an isolated context, so the check is
// written out in full in both rather than shared via a file-level helper.

onRecordCreate(
  (e) => {
    const animalId = e.record.getString("animal");
    let animal;
    try {
      animal = e.app.findRecordById("animals", animalId);
    } catch (_) {
      throw new BadRequestError("Unknown animal.");
    }

    // exams carry an optional `org`; fall back to the parent case's, which is
    // required and org-scoped.
    let orgId = e.record.getString("org");
    if (orgId === "" && e.record.getString("case") !== "") {
      try {
        orgId = e.app
          .findRecordById("cases", e.record.getString("case"))
          .getString("org");
      } catch (_) {
        orgId = "";
      }
    }
    // Nothing to compare against — leave it to the collection's own rules.
    if (orgId === "") {
      e.next();
      return;
    }

    if (animal.getString("org") !== orgId) {
      throw new BadRequestError("Animal belongs to another organisation.");
    }
    e.next();
  },
  "cases",
  "weights",
  "markings",
  "exams",
  "egg_records",
);

onRecordUpdate(
  (e) => {
    const animalId = e.record.getString("animal");

    // Only when `animal` is actually being changed. A cross-org re-point always
    // changes it, so nothing is lost — and rows pointing at a hard-deleted bird
    // may still exist: `cases.animal` only started cascading in 1700000057, so
    // any database older than that can hold cases orphaned by an earlier animal
    // delete. Re-validating every save would make those permanently unsaveable
    // and break unrelated writes like the dispositions hook bumping
    // `case.status`.
    if (animalId === e.record.original().getString("animal")) {
      e.next();
      return;
    }

    let animal;
    try {
      animal = e.app.findRecordById("animals", animalId);
    } catch (_) {
      throw new BadRequestError("Unknown animal.");
    }

    let orgId = e.record.getString("org");
    if (orgId === "" && e.record.getString("case") !== "") {
      try {
        orgId = e.app
          .findRecordById("cases", e.record.getString("case"))
          .getString("org");
      } catch (_) {
        orgId = "";
      }
    }
    if (orgId === "") {
      e.next();
      return;
    }

    if (animal.getString("org") !== orgId) {
      throw new BadRequestError("Animal belongs to another organisation.");
    }
    e.next();
  },
  "cases",
  "weights",
  "markings",
  "exams",
  "egg_records",
);
