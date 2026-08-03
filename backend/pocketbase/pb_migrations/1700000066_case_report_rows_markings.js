/// <reference path="../pb_data/types.d.ts" />

// federfall-dk0c — the annual report (PDF + CSV) needs the bird's markings on
// the report row, so `case_report_rows` (1700000063) grows one column.
//
// Why here and not in the hook: this view IS the definition of "the effective
// table" — the annual report's per-case list and its CSV are the same columns
// rendered two ways (annual_report.pb.js reads this view for both), so a
// column added here lands in both by construction and cannot drift between
// them. That is the whole reason the CSV moved server-side alongside the PDF.
//
// ── `markings` ──────────────────────────────────────────────────────────────
// Only ACTIVE markings, and animal-scoped (`markings` has no `case` — a ring
// is a standing property of the bird, like `egg_records`; see 1700000005 and
// case_report.pb.js's treatment of the same collection). The column therefore
// answers "what would you read off this bird", including a ring from an
// earlier admission — which is exactly what re-identifying a returning bird
// needs. `is_active` is the app's own removal flag (marking_sheet.dart writes
// `true` on create, marking_tile.dart `false` on removal, and
// markings_providers.dart filters the case timeline's "current markings" the
// same way), so a removed temporary marker correctly stops being printed as if
// it were still on the animal. What the org *applied* in the period — removals
// and all — is a separate section of the PDF, queried per-marking by the hook.
//
// Format is "<type label> <code>" per marking, "; "-joined, matching how
// `reasons` already flattens a multi-relation into one cell: group_concat over
// an ordered subquery (SQLite does not promise group_concat ordering, but this
// is the same shape 1700000063 already relies on). The type label comes from
// the `marking_types` code list, so it is user-authored text — never
// translated, same stance as `reasons`.
//
// Everything else about the view (rules, `id`, the terminal-disposition join)
// is unchanged: the collection is fetched and re-saved with a new viewQuery
// rather than dropped and recreated, so the access rules 1700000063 set and
// test_rules.py asserts survive untouched.

migrate(
  (app) => {
    const collection = app.findCollectionByNameOrId("case_report_rows");
    collection.viewQuery = `
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
          SELECT group_concat(m.text, '; ')
          FROM (
            SELECT
              TRIM(
                COALESCE(mt.label, '') ||
                CASE WHEN COALESCE(mk.code, '') != ''
                     THEN ' ' || mk.code ELSE '' END
              ) AS text
            FROM markings mk
            LEFT JOIN marking_types mt ON mt.id = mk.type
            WHERE mk.animal = c.animal AND mk.is_active = 1
            ORDER BY COALESCE(NULLIF(mk.applied_at, ''), mk.created), mk.id
          ) m
          WHERE m.text != ''
        ), '') AS markings,
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
    `;
    app.save(collection);
  },
  (app) => {
    const collection = app.findCollectionByNameOrId("case_report_rows");
    collection.viewQuery = `
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
    `;
    app.save(collection);
  },
);
