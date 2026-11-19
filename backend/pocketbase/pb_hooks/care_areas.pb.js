/// <reference path="../pb_data/types.d.ts" />

// federfall-r67n — a case's `area` is a room its ACTIVE CARER owns, or nothing.
//
// An area is somebody's room (1700000097), so pointing a case at a colleague's
// "Garage" would claim the bird sits in a garage it has never seen. The rule
// cannot say this — "the area's owner equals the case's active carer" compares
// two values of the INCOMING record, and a field reference in an UPDATE rule
// resolves against the stored one (1700000043's finding) — so it is said here.
//
// Two different answers, depending on what moved:
//
//   • the AREA changed to one the carer does not own → refused. That is a
//     request asking for something false, and saying so beats storing it.
//   • the CARER changed (a handoff — placements.pb.js writes it server-side) or
//     the case was CLOSED → the area is emptied, silently. Nobody asked for
//     anything wrong: the room simply belonged to the previous carer, or the
//     bird has left it. Refusing there would make every handoff of a housed
//     bird fail.
//
// On the MODEL events, not the *Request variants, because both writers that
// matter most — the placement handoff and lib_derive.js's disposal — save the
// case server-side, which fires no request hook. Org is not checked here:
// care_areas carries an `org`, so org_scope.pb.js already covers `cases.area`.
//
// JSVM gotcha: each callback runs in an isolated context, so the owner lookup
// is written out in both rather than shared via a file-level helper.

onRecordCreate((e) => {
  const area = e.record.getString("area");
  if (area) {
    let owner = "";
    try {
      owner = e.app.findRecordById("care_areas", area).getString("owner");
    } catch (_) {
      owner = ""; // a missing target fails the relation's own validation
    }
    if (e.record.getString("status") === "disposed") {
      e.record.set("area", "");
    } else if (owner && owner !== e.record.getString("active_carer")) {
      throw new BadRequestError(
        "A case can only be placed in an area of its carer.",
      );
    }
  }
  e.next();
}, "cases");

onRecordUpdate((e) => {
  const rec = e.record;
  const area = rec.getString("area");
  if (area) {
    const moved = area !== rec.original().getString("area");
    let owner = "";
    try {
      owner = e.app.findRecordById("care_areas", area).getString("owner");
    } catch (_) {
      owner = "";
    }
    if (rec.getString("status") === "disposed") {
      rec.set("area", "");
    } else if (owner && owner !== rec.getString("active_carer")) {
      if (moved) {
        throw new BadRequestError(
          "A case can only be placed in an area of its carer.",
        );
      }
      rec.set("area", "");
    }
  }
  e.next();
}, "cases");
