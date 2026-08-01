/// <reference path="../pb_data/types.d.ts" />

// federfall-ye5e — condition_labels: a read-only view of the DISTINCT diagnoses
// actually recorded per org, with the number of cases carrying each.
//
// Two jobs. (1) The case browser's diagnosis filter was populated from the
// `conditions` code list, which both offers entries no case has ever used and
// omits every diagnosis typed as free text — a `case_conditions` row is either
// a code-list reference OR its own `free_text` (1700000006). (2) The statistics
// condition breakdown aggregated the whole `case_conditions` collection on the
// device; `case_count` lets it read one small row set instead (federfall-80tc).
//
// Same shape as `animal_species` (1700000042), which solves the identical
// free-text-vocabulary problem for species. `id` is MIN(case_conditions.id)
// within the group — a real, unique record id, so the view needs no synthetic
// key. Labels are grouped on the resolved display name, so a free-text
// "Katzenbiss" and the code-list entry of the same name are ONE row (and
// `condition` then names the code-list entry). Free text is NOT otherwise
// normalised: "katzenbiss" and "Katzenbiss li. Flügel" stay separate rows,
// which is honest — the view reports what was recorded, it does not guess.
//
// ── Access ──────────────────────────────────────────────────────────────────
// `animal_species` is org-scoped for any active member on the grounds that
// "animals are already org-wide readable, so the distinct kinds leak nothing
// new". That reasoning does NOT carry over here: `case_conditions` is not
// org-wide readable — its list rule is the childView predicate (own case /
// coordinator+supervisor / shared-with). The code-list half of these labels
// leaks nothing (`conditions` is already org-readable), but free text is
// user-typed prose authored on one specific case, so those rows are gated to
// coordinators/supervisors — who already read org-wide. A carer therefore sees
// the recorded code-list vocabulary (no dead options); the free-text tail stays
// with the roles that could read the cases it came from.
//
// `case_count` is org-wide by construction and cannot be per-viewer (a view
// column is computed once, not per request). That is correct for its only
// consumer, the statistics screen, which is coordinator/supervisor-only —
// `statistics_providers.dart` documents the coupling.
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
    // Free-text rows carry no code-list reference, so `condition = ""` is
    // exactly "this label is someone's free text".
    const scoped =
      `${AUTH} && org = @request.auth.org` +
      ` && (condition != "" || ${COORD_SUP})`;

    const view = new Collection({
      type: "view",
      name: "condition_labels",
      listRule: scoped,
      viewRule: scoped,
      viewQuery: `
        SELECT
          MIN(cc.id) AS id,
          cc.org     AS org,
          COALESCE(NULLIF(c.label, ''), cc.free_text) AS label,
          MAX(COALESCE(cc.condition, '')) AS condition,
          COUNT(DISTINCT cc.\`case\`) AS case_count
        FROM case_conditions cc
        LEFT JOIN conditions c ON c.id = cc.condition
        WHERE COALESCE(NULLIF(c.label, ''), cc.free_text) != ''
        GROUP BY cc.org, COALESCE(NULLIF(c.label, ''), cc.free_text)
      `,
    });
    app.save(view);
  },
  (app) => {
    app.delete(app.findCollectionByNameOrId("condition_labels"));
  },
);
