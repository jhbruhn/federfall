/// <reference path="../pb_data/types.d.ts" />

// federfall-c41f — caller-local time, in one place.
//
// Required (INSIDE the handler, `${__hooks}` absolute form — see lib_audit.js)
// by everything that has to render or bucket a timestamp the way the CALLER
// sees it: case_report.pb.js, annual_report.pb.js and stats.pb.js. It lived in
// case_report.pb.js first and was copied into the reporting core; a fix to the
// DST rule or to the date parsing then had to be made twice.
//
// It is its own module rather than part of lib_stats.js because a per-case
// report is not statistics — sharing the code should not mean a receipt
// printer pulls in the annual report's aggregation.
//
// STATELESS, like the other lib_ modules: each pooled JSVM holds its own copy.

// ── Caller-local time ────────────────────────────────────────────────────────
// goja has no Intl and the image carries no tzdata, so a zone name cannot be
// resolved server-side. The client states its own UTC offset instead
// (`?tzOffsetMinutes=`, the same convention case_report.pb.js uses); absent or
// out of range, we fall back to the EU's own Europe/Berlin DST rule, which is
// right for this app's users and never worse than assuming UTC.

const lastSundayUTC = (y, monthIndex) => {
  const lastDay = new Date(Date.UTC(y, monthIndex + 1, 0));
  return lastDay.getUTCDate() - lastDay.getUTCDay();
};

const berlinOffsetMinutes = (utcMs) => {
  const y = new Date(utcMs).getUTCFullYear();
  const dstStart = Date.UTC(y, 2, lastSundayUTC(y, 2), 1, 0, 0);
  const dstEnd = Date.UTC(y, 9, lastSundayUTC(y, 9), 1, 0, 0);
  return (utcMs >= dstStart && utcMs < dstEnd ? 2 : 1) * 60;
};

/**
 * The date helpers for one request, all sharing the caller's offset.
 *
 * `query` is `e.request.url.query()`. `.get()` yields "" (not null) for an
 * absent param — the convention geocode.pb.js and case_report.pb.js follow.
 */
function timeContext(query) {
  const tzParam = parseInt(query.get("tzOffsetMinutes"), 10);
  const explicitOffsetMinutes =
    !isNaN(tzParam) && tzParam >= -720 && tzParam <= 840 ? tzParam : null;
  const offsetFor = (utcMs) =>
    explicitOffsetMinutes !== null
      ? explicitOffsetMinutes
      : berlinOffsetMinutes(utcMs);

  const parseMs = (value) => {
    if (!value) return null;
    const d = new Date(String(value).replace(" ", "T"));
    return isNaN(d.getTime()) ? null : d.getTime();
  };

  // Wall-clock parts in the caller's zone. The Typst templates build a
  // `datetime` from these and format it themselves; the CSV renders them as
  // ISO yyyy-mm-dd; the statistics route buckets on `.y`/`.mo`. Note this is
  // the caller's LOCAL calendar date — formatting PocketBase's UTC instant
  // instead printed 2025-12-31 for a case admitted at 00:30 on New Year's Day
  // in UTC+2, disagreeing with the very year filter that selected it.
  const partsOf = (value) => {
    const ms = parseMs(value);
    if (ms === null) return null;
    const local = new Date(ms + offsetFor(ms) * 60000);
    return {
      y: local.getUTCFullYear(),
      mo: local.getUTCMonth() + 1,
      d: local.getUTCDate(),
      h: local.getUTCHours(),
      mi: local.getUTCMinutes(),
    };
  };

  // The stored PocketBase date format, so a bound can be compared directly by
  // a collection filter.
  const pbStamp = (ms) => new Date(ms).toISOString().replace("T", " ");

  return {
    explicitOffsetMinutes: explicitOffsetMinutes,
    offsetFor: offsetFor,
    parseMs: parseMs,
    partsOf: partsOf,
    pbStamp: pbStamp,
  };
}

module.exports = {
  timeContext: timeContext,
};
