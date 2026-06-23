/// <reference path="../pb_data/types.d.ts" />

// FED-7.6 — case_summaries: an org-wide-readable, clinical-detail-free view of
// the `cases` collection. Powers the animal lifetime record, where ALL of an
// animal's cases must be listed (newest-first) even when the signed-in user
// cannot open the full case.
//
// Why a view (not a relaxed rule on `cases`): the `cases` row itself holds
// clinical fields (intake_notes, exam_*, intake_weight, photos, reasons), and
// PocketBase has no field-level read rules. This view projects ONLY the
// non-clinical summary columns (number, status, find/admit dates), so it can be
// read org-wide without leaking case detail — the same "shared identity layer"
// stance already taken for animals + markings (see FED-1.11). Privacy stays
// enforced at the CASE level: a stub here is not tappable, and the real
// `cases`/child-collection rules still gate all clinical data.
//
// Read-only by nature (view collection). Org-scoped read for any active member.

migrate(
  (app) => {
    const AUTH = '@request.auth.id != "" && @request.auth.is_active = true';
    const orgScoped = `${AUTH} && org = @request.auth.org`;

    const view = new Collection({
      type: "view",
      name: "case_summaries",
      listRule: orgScoped,
      viewRule: orgScoped,
      viewQuery: `
        SELECT
          cases.id            AS id,
          cases.animal        AS animal,
          cases.org           AS org,
          cases.case_number   AS case_number,
          cases.status        AS status,
          cases.admitted_at   AS admitted_at,
          cases.found_at      AS found_at,
          cases.created       AS created
        FROM cases
      `,
    });
    app.save(view);
  },
  (app) => {
    const view = app.findCollectionByNameOrId("case_summaries");
    app.delete(view);
  },
);
