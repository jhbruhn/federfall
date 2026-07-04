/// <reference path="../pb_data/types.d.ts" />

// federfall-d5co.2 — journal_entries becomes dual-parent: a free-text log can
// now be written directly against an aviary (flock-level care — cleaning,
// feed changes, group observations) instead of only against a case. Extends
// the existing collection rather than adding a new one, so nothing about the
// shape duplicates: `case` becomes optional and an optional `aviary` relation
// is added (cascadeDelete, like `case`). Exactly one of the two must be set —
// enforced server-side by the XOR hook in pb_hooks/journal_entries.pb.js,
// since PocketBase rules can't express "exactly one of".
//
// Access is a straight OR of the two parent styles: the existing case-child
// rule (visibility follows the case) when `case` is set, or an aviary-org
// rule (any active member reads, coordinator/supervisor edits — same stance
// as `aviaries` itself) when `aviary` is set.
//
// federfall-621 (1700000043) made `case`/`org` immutable-after-create on this
// collection (`@request.body.<field>:isset = false` on updateRule), closing a
// re-point-into-a-foreign-timeline hole. That guard is re-derived here (with
// `aviary` added to the guarded set) since this migration replaces the whole
// updateRule wholesale.

const ISSET_GUARD =
  ' && @request.body.case:isset = false' +
  ' && @request.body.aviary:isset = false' +
  ' && @request.body.org:isset = false';

migrate(
  (app) => {
    const AUTH = '@request.auth.id != "" && @request.auth.is_active = true && @request.auth.role != "guest"';
    const SUP = '@request.auth.role = "supervisor"';
    const COORD_SUP = '(@request.auth.role = "coordinator" || @request.auth.role = "supervisor")';

    const journal = app.findCollectionByNameOrId("journal_entries");
    const aviaries = app.findCollectionByNameOrId("aviaries");

    const caseField = journal.fields.getByName("case");
    caseField.required = false;

    journal.fields.add(
      new RelationField({
        name: "aviary",
        required: false,
        maxSelect: 1,
        collectionId: aviaries.id,
        cascadeDelete: true,
      }),
    );

    const caseView = `case != "" && case.org = @request.auth.org && (case.active_carer = @request.auth.id || ${COORD_SUP} || case.case_shares_via_case.shared_with ?= @request.auth.id)`;
    const caseEdit = `case != "" && case.org = @request.auth.org && (case.active_carer = @request.auth.id || ${SUP} || (case.case_shares_via_case.shared_with ?= @request.auth.id && case.case_shares_via_case.access ?= "edit"))`;
    const aviaryView = `aviary != "" && aviary.org = @request.auth.org`;
    const aviaryEdit = `aviary != "" && aviary.org = @request.auth.org && ${COORD_SUP}`;

    journal.listRule = `${AUTH} && ((${caseView}) || (${aviaryView}))`;
    journal.viewRule = `${AUTH} && ((${caseView}) || (${aviaryView}))`;
    journal.createRule = `${AUTH} && ((${caseEdit}) || (${aviaryEdit}))`;
    journal.updateRule = `(${AUTH} && ((${caseEdit}) || (${aviaryEdit})))${ISSET_GUARD}`;
    journal.deleteRule = `${AUTH} && ((${caseEdit}) || (${aviaryEdit}))`;

    app.save(journal);
  },
  (app) => {
    const AUTH = '@request.auth.id != "" && @request.auth.is_active = true';
    const SUP = '@request.auth.role = "supervisor"';
    const COORD_SUP = '(@request.auth.role = "coordinator" || @request.auth.role = "supervisor")';
    const childView = `${AUTH} && case.org = @request.auth.org && (case.active_carer = @request.auth.id || ${COORD_SUP} || case.case_shares_via_case.shared_with ?= @request.auth.id)`;
    const childEdit = `${AUTH} && case.org = @request.auth.org && (case.active_carer = @request.auth.id || ${SUP} || (case.case_shares_via_case.shared_with ?= @request.auth.id && case.case_shares_via_case.access ?= "edit"))`;
    // Restore the exact pre-migration state: 1700000043's guard covered only
    // case/org (aviary didn't exist yet).
    const restoredUpdateRule =
      '(' + childEdit + ')' +
      ' && @request.body.case:isset = false' +
      ' && @request.body.org:isset = false';

    const journal = app.findCollectionByNameOrId("journal_entries");
    journal.fields.removeByName("aviary");
    journal.fields.getByName("case").required = true;
    journal.listRule = childView;
    journal.viewRule = childView;
    journal.createRule = childEdit;
    journal.updateRule = restoredUpdateRule;
    journal.deleteRule = childEdit;
    app.save(journal);
  },
);
