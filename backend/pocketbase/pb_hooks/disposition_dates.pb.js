/// <reference path="../pb_data/types.d.ts" />

// federfall-j163 — a disposition cannot have happened tomorrow.
//
// `dispositions.disposed_at` is a bare `date` field (1700000008) with no bound,
// and since federfall-sinp it is the ORDER key: lib_derive.js decides a bird's
// `lifetime_status` and `current_aviary` from the latest event by
// `COALESCE(NULLIF(disposed_at,''), created)`. Since 1700000077 `current_aviary`
// is a custody pointer, so the latest event also decides who may write about the
// bird.
//
// A date in the future is therefore not merely wrong data, it is sticky wrong
// data: a row dated 2099 stays "the latest event" against everything that
// actually happens afterwards, and only a supervisor deleting it (or another
// carer out-dating it) can dislodge it. A disposition is a record of something
// that HAPPENED, so the fix is to refuse the future rather than to teach the
// ordering about it.
//
// ── Why a day of headroom ───────────────────────────────────────────────────
// Not "any future instant": the client sends an absolute UTC timestamp derived
// from its own clock and zone, so a legitimate write can land slightly ahead of
// the server. A day covers the two real causes — a device as far east as UTC+14
// whose local midnight is still tomorrow in UTC, and an unsynchronised clock —
// while leaving nothing exploitable: anything dated inside the window is
// overtaken by real events within hours, which is the whole difference from 2099.
//
// ── Why a model event, not the *Request variant ─────────────────────────────
// This is an invariant about the DATA, not about who is asking, so it holds for
// every writer including the Admin UI and any future hook — and unlike
// animal_custody_scope.pb.js it needs no `e.auth`. Nothing server-side writes a
// future `disposed_at`: intake creates no dispositions, and merge_animals.pb.js
// only re-points existing rows.
//
// ── Not a client-visible tightening ─────────────────────────────────────────
// disposition_sheet.dart picks the date through `pickDate` (ui/widgets/
// date_field.dart), whose `lastDate` defaults to today — so no shipped client
// can produce a value this refuses. It rejects hand-crafted requests only, which
// is why this ships as `fix:` and not `fix!:`.
//
// The update leg fires only when `disposed_at` actually CHANGES, matching
// animal_org_scope's stance: a row that already carries a future date (entered
// before this hook, or by a superuser through an earlier build) must stay
// editable in every other respect — including by the correction that finally
// fixes its date.
//
// JSVM gotcha: each callback runs in an isolated context, so the window and the
// check are written out in full in both rather than shared via a file-level
// const.

onRecordCreate((e) => {
  const at = e.record.getString("disposed_at");
  if (at) {
    // PocketBase stores and returns `YYYY-MM-DD HH:MM:SS.sssZ`; the same shape
    // built from `Date` compares lexicographically against it, which is how
    // lib_derive.js orders these values too.
    const limit = new Date(Date.now() + 24 * 60 * 60 * 1000)
      .toISOString()
      .replace("T", " ");
    if (at > limit) {
      throw new BadRequestError("A disposition cannot be dated in the future.");
    }
  }
  e.next();
}, "dispositions");

onRecordUpdate((e) => {
  const at = e.record.getString("disposed_at");
  if (at && at !== e.record.original().getString("disposed_at")) {
    const limit = new Date(Date.now() + 24 * 60 * 60 * 1000)
      .toISOString()
      .replace("T", " ");
    if (at > limit) {
      throw new BadRequestError("A disposition cannot be dated in the future.");
    }
  }
  e.next();
}, "dispositions");
