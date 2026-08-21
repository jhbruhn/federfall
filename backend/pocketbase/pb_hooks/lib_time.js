/// <reference path="../pb_data/types.d.ts" />

// Moved to zugvogel as zv_time.js. This file is the app's binding, kept so the
// call sites do not have to know where the implementation lives.
//
// A re-export rather than a copy, because a copy is the thing this migration
// exists to remove: two identical files that stay identical only for as long as
// somebody remembers both.

module.exports = require(`${__hooks}/zv_time.js`);
