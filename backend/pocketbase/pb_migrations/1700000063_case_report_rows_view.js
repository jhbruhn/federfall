/// <reference path="../pb_data/types.d.ts" />

// federfall-80tc — case_report_rows: the annual-report CSV (FED-7.3) as one
// pre-joined row per case, so the export stops pulling three whole collections
// (`cases` + `dispositions` + `animals`, every field of each) to a handset just
// to join them there.
//
// Same stance as `condition_labels` (1700000062) and `case_summaries`
// (1700000016): work the device was doing over full collections is work SQL
// already does once, server-side. Everything the CSV prints is here —
// the animal's species/name, the case's terminal outcome + closing date, and
// the admission reasons resolved to their (user-authored) labels — so the app
// reads one small row set, formats it and shares it.
//
// `id` is the case's own id: one row per case, no synthetic key needed.
//
// ── Terminal disposition ────────────────────────────────────────────────────
// A case can be re-disposed, so "the outcome" is the LATEST disposition, dated
// by `disposed_at` falling back to `created` — matching
// `terminalDispositionByCase` in the app (case_facets.dart), which the browser
// facet and the statistics still use. `NULLIF(...,'')` matters: PocketBase
// stores an unset date field as the empty string, not NULL, so a plain
// COALESCE would pick '' over `created` and sort that row to the bottom.
// `d.id` breaks ties so two same-dated dispositions resolve deterministically.
//
// ── Admission reasons ───────────────────────────────────────────────────────
// `cases.admission_reasons` is a multi-relation, i.e. a JSON id array in
// SQLite, so the labels come out of `json_each` joined to the code list and
// concatenated in the order the case recorded them (`je.key`) with the same
// "; " separator the CSV encoder used to apply in Dart. `json_valid` guards
// the empty-string value a case with no reasons carries — `json_each('')`
// raises rather than returning no rows.
//
// ── Access ──────────────────────────────────────────────────────────────────
// Coordinators and supervisors only, within the org. This view is org-wide by
// construction — it joins across every case regardless of carer or share — and
// its only consumer is the statistics screen's CSV export, which is already
// `canViewReports`-gated (coordinator/supervisor) for exactly that reason;
// `statistics_providers.dart` documents the same coupling for the figures.
// Narrower than `case_summaries`, deliberately: this row carries the case's
// find city/region and its admission reasons, which that clinical-detail-free
// view leaves out.
//
// Read-only by nature (view collection). The predicate below is the guest-safe
// form (see 1700000045 and test_rules.py's guest sweep).

migrate(
  (app) => {
    const AUTH =
      '@request.auth.id != "" && @request.auth.is_active = true' +
      ' && @request.auth.role != "guest"';
    const COORD_SUP =
      '(@request.auth.role = "coordinator" || @request.auth.role = "supervisor")';
    const scoped = `${AUTH} && ${COORD_SUP} && org = @request.auth.org`;

    const view = new Collection({
      type: "view",
      name: "case_report_rows",
      listRule: scoped,
      viewRule: scoped,
      viewQuery: `
        SELECT
          c.id          AS id,
          c.org         AS org,
          c.case_number AS case_number,
          c.status      AS status,
          c.admitted_at AS admitted_at,
          c.found_at    AS found_at,
          c.city        AS city,
          c.region      AS region,
          COALESCE(a.species, '') AS species,
          COALESCE(a.name, '')    AS name,
          COALESCE(d.type, '')    AS outcome,
          COALESCE(NULLIF(d.disposed_at, ''), d.created, '') AS ended_at,
          COALESCE((
            SELECT group_concat(r.label, '; ')
            FROM (
              SELECT ar.label AS label
              FROM json_each(
                CASE WHEN json_valid(c.admission_reasons)
                     THEN c.admission_reasons ELSE '[]' END
              ) je
              JOIN admission_reasons ar ON ar.id = je.value
              ORDER BY je.key
            ) r
          ), '') AS reasons
        FROM cases c
        LEFT JOIN animals a ON a.id = c.animal
        LEFT JOIN dispositions d ON d.id = (
          SELECT d2.id
          FROM dispositions d2
          WHERE d2."case" = c.id
          ORDER BY COALESCE(NULLIF(d2.disposed_at, ''), d2.created) DESC,
                   d2.id DESC
          LIMIT 1
        )
      `,
    });
    app.save(view);
  },
  (app) => {
    app.delete(app.findCollectionByNameOrId("case_report_rows"));
  },
);
