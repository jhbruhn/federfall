/// <reference path="../pb_data/types.d.ts" />

// federfall-jo1l / federfall-ti77 — a record's relations must live in its own org.
//
// Registration only; lib_org_scope.js holds the check and the reasoning (why the
// schema drives it rather than a list, what the exposure actually is, and the
// three carve-outs). This file is the one animal_org_scope.pb.js grew into: that
// hook checked `animal` on five collections, and the same hole existed on eleven
// other relations, so the check now asks the schema which relations are
// org-scoped instead of being told.
//
// Deliberately NOT tagged with collection names. A tag list is the hand-kept
// list this replaces: the point is that a collection added tomorrow is covered
// without anybody remembering to come back here. The handler's first act is to
// ask whether this record's collection has any relation worth checking, and for
// most writes the answer costs no query.
//
// MODEL events (onRecordCreate/onRecordUpdate), not the *Request variants: a
// server-side route writes with `tx.save()`, which fires no request hook, and a
// row's org must hold for those writers too — intake.pb.js, exam.pb.js,
// microscopy.pb.js all assemble records from ids they were handed.
// merge_animals.pb.js only ever re-points within one org, so it passes.
// (animal_custody_scope.pb.js is the opposite case and says why: CUSTODY is
// about who is asking, so it needs `e.auth` and therefore a request event.)

onRecordCreate((e) => {
  const bad = require(`${__hooks}/lib_org_scope.js`)
    .foreignRelation(e.app, e.record, true);
  if (bad) {
    throw new BadRequestError("`" + bad + "` belongs to another organisation.");
  }
  e.next();
});

onRecordUpdate((e) => {
  const bad = require(`${__hooks}/lib_org_scope.js`)
    .foreignRelation(e.app, e.record, false);
  if (bad) {
    throw new BadRequestError("`" + bad + "` belongs to another organisation.");
  }
  e.next();
});
