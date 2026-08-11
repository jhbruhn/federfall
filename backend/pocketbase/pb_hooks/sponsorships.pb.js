/// <reference path="../pb_data/types.d.ts" />

// federfall-5s5j.1 — a patronage may only be entered on a bird you keep.
//
// 1700000085's `create` rule is org-scoped only, and says why: "this bird is
// currently in an aviary you keep" is a cross-record invariant, and the body
// form it would need (`@request.body.animal.current_aviary.keeper`) is a two-hop
// resolution this repo has never proven. So the create gate lives here, in the
// one place that can read the incoming `animal` and follow it.
//
// Two conditions, both about the bird rather than the sponsor:
//
//   * the bird must currently be IN an enclosure. A patronage is a patronage of
//     an aviary resident; on a bird in a carer's flat there is nobody the
//     predicate could grant it to, so the row would be invisible to its own
//     author the moment it was written.
//   * the writer must KEEP that enclosure — `lib_custody.js`'s `keeps`, not
//     `holds`. Plain custody is deliberately too wide here: it also answers yes
//     for the active carer of an open case, and a carer is not a reader of the
//     patronage (1700000085's read rule leaves them out on purpose). Granting
//     create to somebody who cannot then list the row would be a write-only
//     door into another keeper's PII view.
//
// A coordinator or supervisor overrides the SECOND condition only, exactly as
// they override every custody gate — they read every sponsorship in the org
// anyway, so nothing is being widened. The first is not a permission and no role
// overrides it: "this bird lives in an enclosure" is a statement about the data.
// A patronage on a bird that lives nowhere is unreadable by every keeper the
// moment it is written, including by whoever wrote it, which is not a row anyone
// meant to create. `sponsorshipWritableBy` (roles.dart) mirrors exactly this
// split, so the app hides the control for a coordinator too.
//
// ── `animal` and `org` are frozen by the RULE, not here ─────────────────────
// 1700000085's update rule carries the `@request.body.<f>:isset = false`
// suffixes (1700000082's shape). This hook deliberately does not re-check them:
// a rule refusal is cheaper and cannot be reached by a writer at all, and one
// guard in two places drifts.
//
// ── Why the *Request variant ────────────────────────────────────────────────
// `e.auth` lives only on RecordRequestEvent (see animal_custody_scope.pb.js /
// disposition_custody.pb.js), and that is also exactly the surface at issue:
// server-side writers and the Admin UI must stay exempt — `merge_animals.pb.js`
// re-points a duplicate's sponsorships with `tx.save()`, which fires no request
// hook, and a superuser bypasses collection rules regardless.
//
// `require()` inside the handler with the `${__hooks}` absolute form: a hook
// handler runs in an isolated JSVM context, so file-level bindings are not in
// scope here (expect ReferenceError otherwise).

onRecordCreateRequest((e) => {
  if (!e.hasSuperuserAuth()) {
    const auth = e.auth;
    const animalId = e.record.getString("animal");
    let aviaryId = "";
    try {
      aviaryId = e.app
        .findRecordById("animals", animalId)
        .getString("current_aviary");
    } catch (_) {
      // An unknown animal: the org-scope guard and the required relation
      // answer that, so say nothing more specific than the refusal below.
      aviaryId = "";
    }
    if (!aviaryId) {
      throw new BadRequestError(
        "A sponsorship can only be recorded for a bird that currently lives " +
          "in an enclosure.",
      );
    }
    const role = auth ? auth.getString("role") : "";
    const override = role === "coordinator" || role === "supervisor";
    if (
      !override &&
      !require(`${__hooks}/lib_custody.js`).keeps(e.app, auth, aviaryId)
    ) {
      throw new ForbiddenError("This bird lives in someone else's enclosure.");
    }
  }
  e.next();
}, "sponsorships");
