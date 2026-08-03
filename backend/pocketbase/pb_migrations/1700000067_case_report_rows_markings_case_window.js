/// <reference path="../pb_data/types.d.ts" />

// federfall-dk0c — narrow `case_report_rows.markings` from "what is on the bird
// NOW" to "what the bird carried at the END of THIS case", and drop the report's
// separate markings section in favour of just this column.
//
// 1700000066 filtered on `is_active`, which is a property of the animal today,
// not of the episode being reported. On a row about a case that closed in 2023
// that is the wrong fact twice over:
//
//   • a ring applied during a LATER admission leaked onto the earlier case's
//     row, implying the bird was ringed before it ever was;
//   • a ring the bird was released with but which was removed afterwards
//     vanished from the very row that should record it.
//
// So the column is now evaluated at the case's own end: the terminal
// disposition's date (the `d` join this view already computes for `ended_at`),
// or now while the case is still open. A marking is in force there when it had
// been applied by then and had not been removed by then — which also answers
// "what was already on it when it arrived", since an arrival ring that stayed on
// is still in force at release. A ring applied on arrival and removed DURING
// care is deliberately not listed: it is not what the bird left with.
//
// `removed_at` is the dated fact and `is_active` only the derived flag (both
// removal paths in the app write the two together — marking_tile.dart and
// animal_detail_screen.dart), so the date decides whenever it is present. When
// it is absent, `is_active` is the only evidence left: 1 means never removed, 0
// means removed at some unrecorded time, and such a marking is dropped rather
// than asserted — an annual report may not claim a bird carried a ring it
// cannot show it still had.
//
// Everything else about the view is unchanged; the collection is re-saved with a
// new viewQuery so 1700000063's access rules survive.

migrate(
  (app) => {
    // The moment the row is reported "as of". Repeated rather than aliased:
    // SQLite cannot reference a select-list alias (`ended_at`) from a
    // correlated subquery in the same select list.
    const AS_OF = `COALESCE(
      NULLIF(d.disposed_at, ''), d.created,
      strftime('%Y-%m-%d %H:%M:%fZ', 'now')
    )`;
    const MARKINGS = `COALESCE((
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
        WHERE mk.animal = c.animal
          AND COALESCE(NULLIF(mk.applied_at, ''), mk.created) <= ${AS_OF}
          AND (
            mk.removed_at > ${AS_OF}
            OR (COALESCE(mk.removed_at, '') = '' AND mk.is_active = 1)
          )
        ORDER BY COALESCE(NULLIF(mk.applied_at, ''), mk.created), mk.id
      ) m
      WHERE m.text != ''
    ), '')`;

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
        ${MARKINGS} AS markings,
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
    // Back to 1700000066's animal-today definition.
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
);
