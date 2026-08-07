/// <reference path="../pb_data/types.d.ts" />

// federfall-vfry — pin the authorship fields to the authenticated caller.
//
// `weights.author`, `vet_appointments.created_by` and the rest of the actor
// relations (lib_authorship.js has the full table) were ordinary client-writable
// fields: no rule pinned them and no hook overwrote them on the direct
// collection paths, so a member could attribute a record to a colleague simply
// by putting that colleague's id in the POST body. The audit log was never
// fooled — lib_audit.js derives its actor from `e.auth`, not from the record —
// but everything the APP shows comes from the record's own field, so a timeline
// tile could credit the wrong carer, and `weights`' delete rule (1700000047)
// and `egg_records`' both hand a row's own author rights over it.
//
// ── Why hooks and not a create rule ─────────────────────────────────────────
// `@request.body.author = @request.auth.id` is the shape `cases` uses for
// active_carer, and it would work — but it REJECTS a create that omits the
// field instead of filling it in, which makes it a wire-contract break for any
// client that doesn't send it (see CLAUDE.md on the major version). Setting the
// value server-side is invisible to a well-behaved client and simply corrects a
// misbehaving one.
//
// ── Why the *Request variants ───────────────────────────────────────────────
// `RecordRequestEvent` is the only event kind carrying `e.auth` (see
// audit_domain.pb.js), and it is also exactly the surface at issue: the
// server-side routes (intake.pb.js, exam.pb.js, merge_animals.pb.js) write with
// `$app.save`, which fires no request hook, and they already set these fields
// from the authenticated user themselves. So this covers the direct collection
// writes and leaves the routes alone.
//
// A superuser write is left untouched: a superuser is not a `users` record, so
// there is no id to pin here that wouldn't dangle.

const authorship = require(`${__hooks}/lib_authorship.js`);

onRecordCreateRequest((e) => {
  const fields = require(`${__hooks}/lib_authorship.js`).ACTOR_FIELDS;
  const field = fields[String(e.record.collection().name)];
  const auth = e.auth;
  if (
    field &&
    !e.hasSuperuserAuth() &&
    auth &&
    String(auth.collection().name) === "users"
  ) {
    e.record.set(field, auth.id);
  }
  e.next();
}, ...authorship.COLLECTIONS);

// Authorship is written once. An update that names someone else is silently
// put back rather than rejected: the app never sends these fields in a PATCH
// body at all, so anything arriving here is either a client echoing the value
// it already has (a no-op) or an attempt to rewrite history.
onRecordUpdateRequest((e) => {
  const fields = require(`${__hooks}/lib_authorship.js`).ACTOR_FIELDS;
  const field = fields[String(e.record.collection().name)];
  if (field && !e.hasSuperuserAuth()) {
    const was = e.record.original().get(field);
    if (String(e.record.get(field)) !== String(was)) {
      e.record.set(field, was);
    }
  }
  e.next();
}, ...authorship.COLLECTIONS);
