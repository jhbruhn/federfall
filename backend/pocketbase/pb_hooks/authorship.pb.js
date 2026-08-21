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

// The stamping is zv_guards.js/zv_authorship.js; the map is lib_authorship.js.
// On UPDATE the stored value is put BACK rather than replaced with the caller —
// "who administered this dose" must not become "who last saved the row". The
// shared helper used to stamp the caller there, which let whoever edited a
// record take authorship of it; fixed in zugvogel 98c011a, with the case that
// separates the two behaviours (the editor naming themselves) as its own test.
// The map is required INSIDE each handler, not read off the `authorship` const
// above. That const is in scope where it is used — the tag list, evaluated at
// registration — and NOT in the handler body, which runs in its own JSVM
// context. Referencing it there fails with `ReferenceError: authorship is not
// defined` at request time, reported as a generic 400 on an ordinary create.
onRecordCreateRequest(
  (e) =>
    require(`${__hooks}/zv_guards.js`).authorship(
      e,
      require(`${__hooks}/lib_authorship.js`).ACTOR_FIELDS,
      true,
    ),
  ...authorship.COLLECTIONS,
);

onRecordUpdateRequest(
  (e) =>
    require(`${__hooks}/zv_guards.js`).authorship(
      e,
      require(`${__hooks}/lib_authorship.js`).ACTOR_FIELDS,
      false,
    ),
  ...authorship.COLLECTIONS,
);
