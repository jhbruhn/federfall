/// <reference path="../pb_data/types.d.ts" />

// federfall-r67n — care areas: the rooms a carer houses their birds in.
//
// A carer asked for exactly this: "Quarantänezimmer", "Garage", "Balkon" — the
// places in their own home a bird can be — so that each open case says where
// its bird currently is, and the case list can be read room by room.
//
// ── An area belongs to a PERSON, not to the org ─────────────────────────────
// The rooms are somebody's flat. Two carers both having a "Garage" are two
// different garages, and a station with shared rooms is just one person (or a
// few) owning those areas. So `owner` is a member, pinned to the caller on
// create and frozen afterwards, and only the owner may rename, reorder or
// delete their own areas. READ is org-wide: a case shared with a colleague, or
// opened by a coordinator, must still be able to say which room its bird is in.
//
// ── `cases.area` is a pointer to the present, not a history ─────────────────
// Where the bird sat last week is not something anybody asked for, and a
// timeline entry per room change would bury the clinical record under
// housekeeping. It is therefore a plain field on the case, and the audit log's
// `case.updated` diff (RELATION_TARGETS `area`) is the only trace of a move.
//
// Because an area is somebody's room, a case may only point at an area its
// ACTIVE CARER owns — care_areas.pb.js refuses anything else, and clears the
// field whenever the case changes hands or is closed, since the room it named
// belongs to the previous carer (or the bird has left it). Deleting an area is
// deliberately unobstructed: the relation is optional and not cascading, so
// PocketBase simply empties it on the cases that named it.
//
// `position` is the owner's own order — the order they walk through their
// home — which is what the case list groups by. Rules use the guest-safe AUTH
// form required since 1700000045.

migrate(
  (app) => {
    const AUTH =
      '@request.auth.id != "" && @request.auth.is_active = true' +
      ' && @request.auth.role != "guest"';
    const ORG_SCOPED = `${AUTH} && org = @request.auth.org`;
    const OWNER = "owner = @request.auth.id";

    const users = app.findCollectionByNameOrId("users");
    const organisations = app.findCollectionByNameOrId("organisations");

    const areas = new Collection({
      type: "base",
      name: "care_areas",
      listRule: ORG_SCOPED,
      viewRule: ORG_SCOPED,
      createRule: `${ORG_SCOPED} && ${OWNER}`,
      updateRule:
        `${ORG_SCOPED} && ${OWNER}` +
        " && @request.body.org:isset = false" +
        " && @request.body.owner:isset = false",
      deleteRule: `${ORG_SCOPED} && ${OWNER}`,
      fields: [
        { name: "name", type: "text", required: true, max: 60 },
        { name: "position", type: "number", required: false, onlyInt: true },
        {
          name: "owner",
          type: "relation",
          required: true,
          maxSelect: 1,
          collectionId: users.id,
          cascadeDelete: true,
        },
        {
          name: "org",
          type: "relation",
          required: true,
          maxSelect: 1,
          collectionId: organisations.id,
          cascadeDelete: false,
        },
        { name: "created", type: "autodate", onCreate: true, onUpdate: false },
        { name: "updated", type: "autodate", onCreate: true, onUpdate: true },
      ],
      indexes: [
        "CREATE INDEX `idx_care_areas_owner` ON `care_areas` (`owner`, `position`)",
      ],
    });
    app.save(areas);

    const cases = app.findCollectionByNameOrId("cases");
    cases.fields.add(
      new RelationField({
        name: "area",
        required: false,
        maxSelect: 1,
        collectionId: areas.id,
        cascadeDelete: false,
      }),
    );
    cases.addIndex("idx_cases_area", false, "`area`", "");
    app.save(cases);
  },
  (app) => {
    const cases = app.findCollectionByNameOrId("cases");
    cases.removeIndex("idx_cases_area");
    cases.fields.removeByName("area");
    app.save(cases);
    app.delete(app.findCollectionByNameOrId("care_areas"));
  },
);
