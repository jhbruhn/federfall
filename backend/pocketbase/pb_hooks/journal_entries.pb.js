/// <reference path="../pb_data/types.d.ts" />

// federfall-d5co.2 — journal_entries is dual-parent (case OR aviary), but
// exactly one must be set; PocketBase rules can't express "exactly one of",
// so it's enforced here on both create and update.

onRecordCreate((e) => {
  const hasCase = e.record.getString("case") !== "";
  const hasAviary = e.record.getString("aviary") !== "";
  if (hasCase === hasAviary) {
    throw new BadRequestError("Exactly one of 'case' or 'aviary' is required.");
  }
  e.next();
}, "journal_entries");

onRecordUpdate((e) => {
  const hasCase = e.record.getString("case") !== "";
  const hasAviary = e.record.getString("aviary") !== "";
  if (hasCase === hasAviary) {
    throw new BadRequestError("Exactly one of 'case' or 'aviary' is required.");
  }
  e.next();
}, "journal_entries");
