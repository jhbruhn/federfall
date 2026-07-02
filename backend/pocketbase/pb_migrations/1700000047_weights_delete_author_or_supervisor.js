/// <reference path="../pb_data/types.d.ts" />

// federfall-p5n — weights delete is no longer org-wide.
//
// 1700000020 moved weights to the animal identity layer (org-wide read/write,
// like markings), but it also made DELETE org-wide — any carer could silently
// erase another carer's clinical weight history. The other identity-layer
// collections reserve delete for supervisors (1700000010). Weights keep one
// extra allowance: the record's `author` may delete their own entry, so the
// app's correct-a-typo path (weight tile delete) keeps working for the person
// who logged it. Create/update stay org-wide — the issue is destruction, not
// contribution.
//
// The predicate is the guest-safe form required since 1700000045.

migrate(
  (app) => {
    const AUTH =
      '@request.auth.id != "" && @request.auth.is_active = true' +
      ' && @request.auth.role != "guest"';
    const weights = app.findCollectionByNameOrId("weights");
    weights.deleteRule =
      `${AUTH} && org = @request.auth.org && ` +
      '(@request.auth.role = "supervisor" || author = @request.auth.id)';
    app.save(weights);
  },
  (app) => {
    // Restore the org-wide delete that 1700000020 set (as rewritten to the
    // guest-safe form by 1700000045, the state this migration replaced).
    const AUTH =
      '@request.auth.id != "" && @request.auth.is_active = true' +
      ' && @request.auth.role != "guest"';
    const weights = app.findCollectionByNameOrId("weights");
    weights.deleteRule = `${AUTH} && org = @request.auth.org`;
    app.save(weights);
  },
);
