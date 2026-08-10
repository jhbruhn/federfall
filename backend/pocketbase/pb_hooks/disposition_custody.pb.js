/// <reference path="../pb_data/types.d.ts" />

// federfall-mpm4 — an outcome that moves a bird needs current custody of it.
//
// The residual half of federfall-j163. That one bounded WHEN a disposition may
// say it happened (nothing more than a day ahead); this bounds WHO may write one
// that changes where the bird lives — because since 1700000077 `current_aviary`
// is a custody pointer, and `lib_derive.js` derives it from the LATEST event.
// A carer whose case closed in 2024 is still its `active_carer` (that never
// expires) and so still passes 1700000010's `childEdit` on its dispositions:
// adding a `placed_in_aviary` naming their own enclosure, dated yesterday, made
// them the custodian of a bird in somebody else's care.
//
// The whole gate — when it fires, what it allows, and why it is not plain
// custody — is `lib_custody.js`'s `requireOutcomeWrite`. It lives there rather
// than here because each of these three callbacks runs in its own isolated JSVM,
// so anything shared between them has to be a required module (the same reason
// lib_derive.js exists), and because the question it answers is a custody
// question.
//
// The delete leg carries federfall-epkf's second door as well: deleting a case's
// last disposition re-opens the case and hands custody back to its carer, which
// is the same act `case_status.pb.js` refuses through the `status` field.
//
// federfall-q11w is why the moving leg is plain custody with no correction
// exemption: the weaker predicate that would have let a carer repair the
// placement they just recorded equally let a stale one evict somebody else's
// resident, and no reading of the state can tell those apart. Once a bird is
// handed over it is the enclosure's; repairs are the keeper's or a supervisor's.
//
// Why the *Request variants: `e.auth` lives only on RecordRequestEvent (see
// animal_custody_scope.pb.js / authorship.pb.js), and the server-side writers
// must stay exempt — merge_animals.pb.js re-points a duplicate's dispositions
// with `tx.save()`, which fires no request hook. Superuser is exempt as
// everywhere else; it bypasses collection rules anyway.

onRecordCreateRequest((e) => {
  if (!e.hasSuperuserAuth()) {
    require(`${__hooks}/lib_custody.js`)
      .requireOutcomeWrite(e.app, e.auth, e.record, false);
  }
  e.next();
}, "dispositions");

onRecordUpdateRequest((e) => {
  if (!e.hasSuperuserAuth()) {
    require(`${__hooks}/lib_custody.js`)
      .requireOutcomeWrite(e.app, e.auth, e.record, false);
  }
  e.next();
}, "dispositions");

onRecordDeleteRequest((e) => {
  if (!e.hasSuperuserAuth()) {
    require(`${__hooks}/lib_custody.js`)
      .requireOutcomeWrite(e.app, e.auth, e.record, true);
  }
  e.next();
}, "dispositions");
