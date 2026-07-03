/// <reference path="../pb_data/types.d.ts" />

// FED-8.1 — finder PII retention (GDPR/DSGVO data minimisation).
//
// A "finder" is an external member of the public who brought a bird in; their
// record holds identifying PII (name, contact). Once their case(s) are closed
// there is no longer a reason to keep that personal data, so a daily job
// anonymises finders whose cases all ended longer ago than the org's retention
// window (default 2 years).
//
// What is scrubbed: identity + contact + the freeform notes field. What is KEPT:
// the location (address, postal_code, city, region) — useful as non-identifying
// "where do birds come from" data — plus the org link and timestamps. The record
// is kept (not deleted) so the case→finder link and that location survive; it is
// marked pii_purged = true so the job never reprocesses it.
//
// The window is org-configurable via organisations.settings JSON:
//   { "finder_retention_years": 2 }
//
// PocketBase isolates each handler's JSVM context, so everything is defined
// inside the handler (file-level helpers are not visible here).

cronAdd("finderPiiRetention", "0 3 * * *", () => {
  const DEFAULT_RETENTION_YEARS = 2;
  const YEAR_MS = 365 * 24 * 60 * 60 * 1000;
  const PAGE = 200;

  // Identity + contact + freeform notes. Location fields are intentionally kept.
  const PII_FIELDS = [
    "first_name",
    "last_name",
    "organisation",
    "phone",
    "alt_phone",
    "email",
    "notes",
  ];

  const now = new Date();

  const toDate = (s) => {
    if (!s) return null;
    const d = new Date(String(s).replace(" ", "T"));
    return isNaN(d.getTime()) ? null : d;
  };

  const retentionMsForOrg = (orgId) => {
    let years = DEFAULT_RETENTION_YEARS;
    try {
      const org = $app.findRecordById("organisations", orgId);
      const settings = org.get("settings");
      if (settings && settings.finder_retention_years) {
        const y = parseFloat(settings.finder_retention_years);
        if (!isNaN(y) && y > 0) years = y;
      }
    } catch (_) {
      // no org / no settings → default window
    }
    return years * YEAR_MS;
  };

  // Latest "case ended" date for a finder, or null if any case is still active.
  // Reads dispositions directly — a case is "ended" once its status is disposed,
  // and the end date is the latest disposition's server-side `created` autodate.
  // We deliberately do NOT use disposed_at: it's a client-writable field, so a
  // carer with edit access could backdate it to accelerate (or delay) when this
  // finder's PII gets scrubbed — `created` is set by PocketBase and can't be
  // forged from the client. (We also don't read the case_summaries view here:
  // its computed ended_at column doesn't round-trip reliably through the record
  // model from a hook.) Returns { active, latestEnd, hasCases }.
  const caseEndInfo = (finderId) => {
    const cases = $app.findRecordsByFilter(
      "cases",
      "finder = {:fid}",
      "",
      PAGE,
      0,
      { fid: finderId },
    );
    if (cases.length === 0) {
      return { active: false, latestEnd: null, hasCases: false };
    }
    let latest = null;
    for (const c of cases) {
      if (c.getString("status") !== "disposed") {
        return { active: true, latestEnd: null, hasCases: true };
      }
      const disps = $app.findRecordsByFilter(
        "dispositions",
        "case = {:c}",
        "",
        PAGE,
        0,
        { c: c.id },
      );
      for (const d of disps) {
        const end = toDate(d.getString("created"));
        if (end && (!latest || end > latest)) latest = end;
      }
      // A disposed case with no disposition row is unexpected — fall back to the
      // case's own updated time so it still ages out rather than lingering.
      if (disps.length === 0) {
        const end = toDate(c.getString("updated"));
        if (end && (!latest || end > latest)) latest = end;
      }
    }
    return { active: false, latestEnd: latest, hasCases: true };
  };

  let scrubbed = 0;
  let offset = 0;
  // Page through finders that still hold PII. Each scrub sets pii_purged = true,
  // so processed rows drop out of the filter; keep offset at 0 and re-query.
  for (;;) {
    let batch;
    try {
      batch = $app.findRecordsByFilter(
        "finders",
        "pii_purged = false",
        "created",
        PAGE,
        offset,
      );
    } catch (e) {
      $app.logger().warn("finder retention: query failed", "err", String(e));
      break;
    }
    if (!batch || batch.length === 0) break;

    let scrubbedThisBatch = 0;
    for (const finder of batch) {
      try {
        const st = caseEndInfo(finder.id);
        if (st.active) continue; // a case is still open → keep PII

        // Reference date: latest case end, or the finder's creation if it was
        // never linked to a case (orphan).
        const ref = st.hasCases ? st.latestEnd : toDate(finder.getString("created"));
        if (!ref) continue;

        const windowMs = retentionMsForOrg(finder.getString("org"));
        if (now.getTime() - ref.getTime() < windowMs) continue;

        for (const f of PII_FIELDS) finder.set(f, "");
        finder.set("pii_purged", true);
        $app.save(finder);
        scrubbed++;
        scrubbedThisBatch++;
      } catch (e) {
        $app.logger().warn("finder retention: scrub failed", "finder", finder.id, "err", String(e));
      }
    }

    // If nothing in this page was scrubbed, advance past it; otherwise the
    // scrubbed rows already left the filter, so re-query from the same offset.
    if (scrubbedThisBatch === 0) offset += batch.length;
  }

  if (scrubbed > 0) {
    $app.logger().info("finder retention: anonymised finders past retention", "count", scrubbed);
  }
});
