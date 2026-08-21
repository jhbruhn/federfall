/// <reference path="../pb_data/types.d.ts" />

// Moved to zugvogel as zv_org.js — the ONE reader of `organisations.settings`.
//
// That trap is worth restating where a reader will look: `record.get(<json
// field>)` hands JS a byte array, so `settings.someKey` is always `undefined`
// and the caller silently falls through to its default. It had been written five
// times in this repo, correctly in three; the two wrong ones silently disabled a
// GDPR retention window and a quarantine default for every org. One reader means
// one place left to get it wrong.
//
// zugvogel's version also offers `positiveNumberList` for ladder settings, which
// federfall does not use yet.

module.exports = require(`${__hooks}/zv_org.js`);
