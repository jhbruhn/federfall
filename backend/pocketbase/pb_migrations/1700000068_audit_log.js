/// <reference path="../pb_data/types.d.ts" />

// federfall-qt96.1 — audit_events: org-scoped, append-only, supervisor-only log
// of who did what, with metadata.
//
// An event is an ENVELOPE plus a typed DETAIL, never a pre-rendered sentence:
// the app translates a stable `action` code into German/English itself. The hard
// rule the schema exists to support is that the envelope ALONE must render a
// usable line — `detail` only enriches it. That is what makes "add a new action"
// additive under this repo's major-version wire contract: an older client seeing
// an unknown action renders a generic envelope line instead of breaking, so new
// actions ship as `feat:`, not `feat!:`.
//
// ── Why so many plain TEXT columns where a relation looks natural ────────────
//
// `subject_*`, `case_id` and `actor_id` are TEXT, not relations, for two
// separate reasons — both of which are really the same reason: an audit row must
// outlive the thing it describes.
//
//  1. Supervisor deletes cascade hard (cases.animal since 1700000057): deleting
//     an animal takes its cases and their whole timeline. A relation would drag
//     the log down with them (cascadeDelete: true) or, at best, blank out the
//     one field that says WHAT was acted on.
//  2. cascadeDelete: false is not an escape either — it is what forced `actor_id`
//     to be TEXT as well, deviating from the epic's design sketch. When a
//     referenced record is deleted, PocketBase NULLIFIES the non-cascade
//     relations pointing at it by SAVING each referring record, which fires the
//     ordinary update hooks (main.pb.js §3 documents exactly this: PB stripping
//     a deleted member from `cases.active_carer` runs the share-on-handoff hook,
//     and a throw there aborts the member removal). The append-only guard in
//     pb_hooks/audit.pb.js throws on EVERY update with no carve-out — so had
//     `actor` stayed a relation, deleting a user who appears in one audit row
//     would fail with 400 and user management would seize up the first time
//     anyone was audited. Text has no such coupling.
//
// The snapshot columns (`actor_label`, `actor_role`, `subject_label`) are the
// compensating control: the log still says who did what to which bird after both
// records are gone.
//
// `org` is the one relation kept, because it is the scoping boundary the access
// rule compares against and because it introduces nothing new: a required
// non-cascade relation already makes an organisation undeletable while any row
// references it, which `cases.org` and `animals.org` have done since 1700000002.
// Users, by contrast, are deleted routinely.
//
// ── Why `action` and `severity` are TEXT, not `select` ───────────────────────
//
// Emitters run INSIDE domain transactions. A `select` field rejecting an
// unlisted value would throw there and turn a legitimate write into a 400 — an
// audit log that can break the thing it observes is worse than one with a typo
// in it. Validity is enforced by the ACTIONS registry in pb_hooks/lib_audit.js
// plus the coverage test (federfall-qt96.7), where a failure costs a red test
// instead of a lost case record.
//
// ── There is no `updated` autodate, deliberately ─────────────────────────────
//
// Every other collection here carries one. A row that can never be updated has
// nothing to stamp, and the missing column is a second, structural statement of
// the same invariant the hook enforces.
//
// ── Access rules ARE the append-only boundary ────────────────────────────────
//
// Hooks write via app.save(), which bypasses rules entirely — so nulling all
// three write rules costs the emitters nothing and makes the collection
// unwritable AND unerasable through the API for every caller, superuser
// dashboard aside (that one is covered by pb_hooks/audit.pb.js).
//
// The `role != "guest"` clause is redundant after `role = "supervisor"`, but the
// guest-safe form is mandatory for every migration copying the shared auth
// predicate (1700000045) and test_rules.py's guest sweep is written to expect
// it. Supervisor-only is a decision, not a limitation: widening to coordinators
// later tightens nothing, so it stays non-breaking in either direction.
//
// ── NON-GOAL: no hash chain ──────────────────────────────────────────────────
//
// Deliberately omitted. It only detects tampering by someone who already has the
// SQLite file — i.e. someone who can also rewrite the chain — and doing it
// correctly requires serialising every single event behind the write-lock trick
// `case_number` uses (1700000046), which would put a global bottleneck in front
// of every audited write in the app. The threat it actually addresses (an
// operator editing history through the Admin UI) is covered by the hook guard at
// a fraction of the cost.

migrate(
  (app) => {
    const organisations = app.findCollectionByNameOrId("organisations");

    app.save(
      new Collection({
        type: "base",
        name: "audit_events",
        indexes: [
          // The feed, and the three ways it is ever narrowed. Each leads with
          // `org` because that is the scoping boundary — no query crosses it.
          "CREATE INDEX `idx_audit_events_org_created` ON `audit_events` (`org`, `created`)",
          "CREATE INDEX `idx_audit_events_org_case` ON `audit_events` (`org`, `case_id`, `created`)",
          "CREATE INDEX `idx_audit_events_org_actor` ON `audit_events` (`org`, `actor_id`, `created`)",
          "CREATE INDEX `idx_audit_events_org_action` ON `audit_events` (`org`, `action`, `created`)",
        ],
        fields: [
          {
            name: "org",
            type: "relation",
            required: true,
            maxSelect: 1,
            collectionId: organisations.id,
            cascadeDelete: false,
          },
          // `domain.verb`, e.g. "case.handoff". See the header on why not select.
          { name: "action", type: "text", required: true, max: 64 },

          // ── actor: who did it, as snapshots (see header) ──────────────────
          { name: "actor_id", type: "text", required: false, max: 32 },
          { name: "actor_label", type: "text", required: false, max: 200 },
          { name: "actor_role", type: "text", required: false, max: 32 },
          // user | system | cron | superuser
          { name: "actor_kind", type: "text", required: false, max: 16 },

          // ── subject: what was acted on, as snapshots (see header) ─────────
          { name: "subject_collection", type: "text", required: false, max: 64 },
          { name: "subject_id", type: "text", required: false, max: 32 },
          // NEVER holds finder PII — a finder subject carries "" here, or the
          // audit trail would defeat finder_retention.pb.js's GDPR scrub.
          { name: "subject_label", type: "text", required: false, max: 200 },

          // The one hot query ("everything that happened on this case") gets a
          // real indexed column instead of a json lookup into `refs`.
          { name: "case_id", type: "text", required: false, max: 32 },

          // Other ids touched: {animal, user, aviary, disposition, …}.
          { name: "refs", type: "json", required: false, maxSize: 5000 },
          // [{field, from, to}] — kept OUT of `detail` so one generic renderer
          // handles every `*.updated` action. Sensitive values are redacted to
          // {field, redacted: true} by the emitter, which keeps the FACT of the
          // change while dropping the value. A relation-valued field carries
          // `from_label`/`to_label` beside the ids: what the target was CALLED
          // when the row was written, since it can be renamed or deleted later.
          { name: "changes", type: "json", required: false, maxSize: 20000 },
          // The action-specific typed payload.
          { name: "detail", type: "json", required: false, maxSize: 20000 },

          // info | notice | security — lets the UI filter role/share/auth
          // events out of the day-to-day noise.
          { name: "severity", type: "text", required: false, max: 16 },

          // Personal data about staff: written ONLY when the org opts in via
          // settings.auditLogClientInfo === true (default off).
          { name: "ip", type: "text", required: false, max: 64 },
          { name: "user_agent", type: "text", required: false, max: 512 },

          // Correlates the rows of one request — an intake writes several
          // records under a single id.
          { name: "request_id", type: "text", required: false, max: 64 },

          // The timestamp. Sort key is (created, id); no `updated` by design.
          { name: "created", type: "autodate", onCreate: true, onUpdate: false },
        ],
      }),
    );

    const AUTH =
      '@request.auth.id != "" && @request.auth.is_active = true' +
      ' && @request.auth.role != "guest"';
    const SUP = '@request.auth.role = "supervisor"';
    const read = `${AUTH} && ${SUP} && org = @request.auth.org`;

    const c = app.findCollectionByNameOrId("audit_events");
    c.listRule = read;
    c.viewRule = read;
    // Hooks bypass rules; nothing else may ever write here.
    c.createRule = null;
    c.updateRule = null;
    c.deleteRule = null;
    app.save(c);
  },
  (app) => {
    app.delete(app.findCollectionByNameOrId("audit_events"));
  },
);
