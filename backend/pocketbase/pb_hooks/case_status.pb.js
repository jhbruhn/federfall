/// <reference path="../pb_data/types.d.ts" />

// federfall-epkf — a case's status may not contradict its outcome.
//
// `cases.status` carried no guard of any kind. 1700000075 isset-guards the
// derived fields on `animals`, 1700000081/1700000082 freeze the relations, but
// `status` is an ordinary select field and `cases.update` is 1700000010's
// `caseEdit` — `active_carer = auth.id || supervisor || edit-share` — with no
// clause about it. `active_carer` of a DISPOSED case never expires, so the carer
// of a case closed years ago could
//
//     PATCH /api/collections/cases/records/<their old case>  {"status": "in_care"}
//
// and 1700000077's custody predicate (`cases_via_animal.active_carer ?= auth.id
// && cases_via_animal.status ?= "in_care"`) matched again: they held the bird,
// including one in another carer's acute care. Verified against a live 0.39.8.
//
// ── Why the invariant rather than a custody clause ──────────────────────────
// Because there was never a workflow behind that write. `status` is DERIVED
// wherever a disposition exists: lib_derive.js's `reconcileCase` sets `disposed`
// when the case carries one and `in_care` when the last one is deleted, and
// deleting the disposition IS the correction path for an outcome entered by
// mistake (disposition_sheet.dart's delete action). The app never sends the
// transition this refuses — case_detail_screen.dart's `_CaseActions` renders no
// status control at all once a case is disposed — so what is left is the
// hand-crafted request, and the honest way to describe it is not "you lack
// authority" but "that would make the record say two different things".
//
// So: a case that carries a disposition is disposed, and one that carries none
// is not. `in_care <-> ready_for_release` stays freely writable by anyone who may
// edit the case, which is the only status change the UI offers.
//
// The other direction is refused for the same reason and is worth as much: a case
// PATCHed to `disposed` with no disposition falls out of the case browser's
// active set (`in_care || ready_for_release || ""`, federfall-jt5u) while never
// appearing as an ended case in `case_report_rows`, whose `ended_at` comes from
// the terminal disposition — a case that has quietly left both lists.
//
// federfall-mpm4's `disposition_custody.pb.js` covers the second door into the
// same place: deleting a case's last disposition re-opens the case legitimately,
// so it is gated on custody of the bird instead of forbidden.
//
// ── Shape ───────────────────────────────────────────────────────────────────
// *Request variants, so the derivation itself stays exempt: `reconcileCase` and
// main.pb.js §2 write `status` with `app.save()`, which fires no request hook,
// and intake.pb.js creates its case inside a transaction the same way. Superuser
// is exempt as everywhere else (it bypasses collection rules anyway), which also
// keeps the Admin UI able to repair a row this refuses.
//
// The update leg fires only when `status` actually CHANGES, matching
// disposition_dates.pb.js and animal_custody_scope.pb.js: a case whose stored
// status already contradicts its outcome — imported, or written before this hook
// — must stay editable in every other respect, including by the correction that
// finally fixes it.
//
// JSVM gotcha: each callback runs in an isolated context, so the disposition
// lookup is written out in both rather than shared via a file-level helper.

onRecordCreateRequest((e) => {
  // A case cannot be created already ended: it has no disposition yet by
  // definition, and nothing creates one this way — the app opens cases through
  // `/api/federfall/intake`, which writes them server-side.
  if (!e.hasSuperuserAuth() && e.record.getString("status") === "disposed") {
    throw new BadRequestError(
      "A case cannot be closed before it has an outcome.",
    );
  }
  e.next();
}, "cases");

onRecordUpdateRequest((e) => {
  if (!e.hasSuperuserAuth()) {
    const status = e.record.getString("status");
    if (status !== e.record.original().getString("status")) {
      let outcomes = [];
      try {
        outcomes = e.app.findRecordsByFilter(
          "dispositions", "case = {:c}", "", 1, 0, { c: e.record.id },
        );
      } catch (_) {
        outcomes = [];
      }
      if (outcomes.length > 0 && status !== "disposed") {
        throw new BadRequestError(
          "This case has a recorded outcome; delete the outcome to re-open it.",
        );
      }
      if (outcomes.length === 0 && status === "disposed") {
        throw new BadRequestError(
          "A case cannot be closed before it has an outcome.",
        );
      }
    }
  }
  e.next();
}, "cases");
