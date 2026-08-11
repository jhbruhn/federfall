/// <reference path="../pb_data/types.d.ts" />

// federfall — vaccine_labels: a read-only view of the DISTINCT (vaccine,
// target) pairs actually recorded per org, with how often each was used and
// when it was last used.
//
// This is the vocabulary half of 1700000087's decision to keep `vaccine` and
// `target` free TEXT. Same shape and same argument as `animal_species`
// (1700000042) and `condition_labels` (1700000062): a list built out of use
// offers nothing dead, needs no seeding, and cannot go stale — where a
// supervisor-managed product list would need curating before anyone could
// record anything, and would inherit federfall-buqb (code lists are not seeded
// for orgs created after their migration).
//
// One row per (org, vaccine, target), rather than two views over two columns.
// The pair is what a carer actually needs: choosing "Colombovac PMV" can
// prefill the target that product covers, because the pairing is a recorded
// fact rather than a guess. A vaccine typed with two different targets is
// honestly two rows.
//
// `id` is MIN(vaccinations.id) within the group — a real, unique record id
// (each vaccination belongs to exactly one group), so the view needs no
// synthetic key. Rows with an empty `vaccine` are excluded; an empty `target`
// is kept, because "recorded without a target" is a real state and hiding it
// would make the product itself unsuggestable.
//
// Nothing is normalised: "PMV" and "Paramyxovirose" stay two rows. That is
// deliberate and matches `condition_labels` — the view reports what was
// recorded, it does not guess. Converging the two is the suggestion list's job
// at the point of entry, not a rewrite of anyone's record after the fact.
//
// `last_used_at` exists so suggestions can be ranked by recency rather than
// alphabetically: the thing this org vaccinated with last month is the likely
// answer. It uses the same COALESCE(NULLIF(...)) fallback to `created` that the
// model and every other dated record here use for an optional event date.
//
// ── Access ──────────────────────────────────────────────────────────────────
// `animal_species`'s argument applies verbatim and `condition_labels`'s
// exception does not: `vaccinations` is org-wide READABLE by design
// (1700000087), so the distinct values leak nothing a member cannot already
// read row by row. No coordinator gate, therefore. Guest-safe AUTH form
// (1700000045); read-only by nature.
//
// Note for anyone reading this view from a HOOK rather than over REST:
// `use_count` and `last_used_at` are computed, so PocketBase cannot trace them
// back to a real field and types them `json` — getString() would return raw
// JSON, quotes included (federfall-dk0c). The REST API decodes on the way out,
// so the app is unaffected; a future server-side reader is not.

migrate(
  (app) => {
    const AUTH =
      '@request.auth.id != "" && @request.auth.is_active = true' +
      ' && @request.auth.role != "guest"';
    const orgScoped = `${AUTH} && org = @request.auth.org`;

    const view = new Collection({
      type: "view",
      name: "vaccine_labels",
      listRule: orgScoped,
      viewRule: orgScoped,
      viewQuery: `
        SELECT
          MIN(v.id)  AS id,
          v.org      AS org,
          v.vaccine  AS vaccine,
          v.target   AS target,
          COUNT(*)   AS use_count,
          MAX(COALESCE(NULLIF(v.administered_at, ''), v.created))
                     AS last_used_at
        FROM vaccinations v
        WHERE v.vaccine != ''
        GROUP BY v.org, v.vaccine, v.target
      `,
    });
    app.save(view);
  },
  (app) => {
    app.delete(app.findCollectionByNameOrId("vaccine_labels"));
  },
);
