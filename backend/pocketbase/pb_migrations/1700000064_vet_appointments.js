/// <reference path="../pb_data/types.d.ts" />

// federfall-fnpo — vet_appointments: a booked visit at a vet on a case, with a
// time of day, the practice, the reason it was booked, and the outcome written
// after the visit.
//
// Deliberately NOT `follow_ups`, whose own header already claims "vet visit next
// week": a follow-up is a date-only self-recheck with one note and a done stamp.
// An appointment differs in three ways the worklist has to see — it has a time
// of day, it involves an external party, and its outcome is not the same text as
// the reason it was booked. Sharing one collection would leave the worklist
// unable to tell "check the bird today" from "be at Dr. Meyer at 14:30".
//
// `attended_at` and `cancelled_at` are separate stamps on purpose. Cancelled is
// not "not yet attended": both end the appointment's claim on the worklist, but
// only one of them means the bird was seen.
//
// `reminder_lead_minutes` / `reminder_muted` are the per-appointment override of
// the device-wide reminder lead. Two fields rather than a sentinel because
// PocketBase has no null for a number field (clearing one stores 0), so a lone
// integer cannot distinguish "follow the device default" from "no reminder".
// `min: 1` follows medications' `interval_hours`. Note it does NOT reject 0 —
// PocketBase skips min/max for a zero on an optional number field, so 0 stays
// indistinguishable from unset and the client reads it as "use the default"
// (see VetAppointment.fromRecord). What min buys is rejecting a NEGATIVE, so no
// client can smuggle in a sentinel the mapper would misread as a real lead.
//
// Case-scoped access mirrors the other child collections (FED-1.11), in the
// guest-safe form every migration after 1700000045 must ship itself. Nothing
// derives from an appointment, so it needs no hook: `cascadeDelete` on `case`
// ties it into the supervisor-only case delete like every other case relation.
// Self-contained migration.

migrate(
  (app) => {
    const cases = app.findCollectionByNameOrId("cases");
    const users = app.findCollectionByNameOrId("users");
    const organisations = app.findCollectionByNameOrId("organisations");

    app.save(
      new Collection({
        type: "base",
        name: "vet_appointments",
        fields: [
          {
            name: "case",
            type: "relation",
            required: true,
            maxSelect: 1,
            collectionId: cases.id,
            cascadeDelete: true,
          },
          { name: "starts_at", type: "date", required: true },
          { name: "vet", type: "text", required: false, presentable: true, max: 200 },
          { name: "reason", type: "text", required: false, max: 2000 },
          { name: "outcome", type: "text", required: false, max: 2000 },
          { name: "attended_at", type: "date", required: false },
          { name: "cancelled_at", type: "date", required: false },
          { name: "reminder_lead_minutes", type: "number", required: false, min: 1, onlyInt: true },
          { name: "reminder_muted", type: "bool", required: false },
          {
            name: "created_by",
            type: "relation",
            required: false,
            maxSelect: 1,
            collectionId: users.id,
          },
          {
            name: "org",
            type: "relation",
            required: false,
            maxSelect: 1,
            collectionId: organisations.id,
          },
          { name: "created", type: "autodate", onCreate: true, onUpdate: false },
          {
            name: "updated",
            type: "autodate",
            onCreate: true,
            onUpdate: true,
          },
        ],
      }),
    );

    const AUTH =
      '@request.auth.id != "" && @request.auth.is_active = true' +
      ' && @request.auth.role != "guest"';
    const SUP = '@request.auth.role = "supervisor"';
    const COORD_SUP =
      '(@request.auth.role = "coordinator" || @request.auth.role = "supervisor")';
    const childView = `${AUTH} && case.org = @request.auth.org && (case.active_carer = @request.auth.id || ${COORD_SUP} || case.case_shares_via_case.shared_with ?= @request.auth.id)`;
    const childEdit = `${AUTH} && case.org = @request.auth.org && (case.active_carer = @request.auth.id || ${SUP} || (case.case_shares_via_case.shared_with ?= @request.auth.id && case.case_shares_via_case.access ?= "edit"))`;

    const c = app.findCollectionByNameOrId("vet_appointments");
    c.listRule = childView;
    c.viewRule = childView;
    c.createRule = childEdit;
    c.updateRule = childEdit;
    c.deleteRule = childEdit;
    app.save(c);
  },
  (app) => {
    app.delete(app.findCollectionByNameOrId("vet_appointments"));
  },
);
