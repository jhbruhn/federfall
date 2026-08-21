import 'package:federfall/features/admin/codelist_admin.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zugvogel_ui/zugvogel_ui.dart'
    show confirmAndDelete, runQuickAction;

/// Confirms, then deletes **or deactivates** the code-list [entry]
/// (federfall-58t1).
///
/// Deleting a code-list entry is the highest-blast-radius single tap in the
/// app, and what PocketBase does with the records pointing at it depends on the
/// relation — verified against a live instance:
///
/// - `markings.type` is a **required** relation, so the delete is rejected
///   outright (`Make sure that the record is not part of a required relation
///   reference`). This used to surface as that raw error message.
/// - the other three lists are referenced by *optional* relations, so the
///   delete succeeds and PocketBase silently **blanks** the field on every
///   referencing record: a diagnosis with no condition, a case that has lost an
///   admission reason, a prescription with no route. Nothing is orphaned —
///   the information is simply gone.
///
/// So the dialog states the count first, and offers the reversible alternative
/// the code lists already have: an `active` flag whose consumers deliberately
/// keep a deactivated entry visible on records that already reference it.
/// Deactivating preserves history, deleting destroys it, so deactivating is the
/// primary button and the delete is demoted (or absent, where the server would
/// refuse it anyway).
///
/// Supervisor-only, like the screen it is reached from; the server rules
/// (1700000010) remain the real boundary.
Future<void> confirmCodelistDelete<T>(
  BuildContext context,
  WidgetRef ref, {
  required CodelistSpec<T> spec,
  required T entry,
}) async {
  final l10n = context.l10n;
  final id = spec.id(entry);

  // AWAITED, and through [runQuickAction] so a failure is reported rather than
  // swallowed: a count that silently degraded to 0 would turn "40 cases use
  // this" into an unqualified "delete?" on the one dialog that must not
  // understate the damage.
  int? counted;
  await runQuickAction(context, () async {
    counted = await spec.countReferences(ref, entry);
  });
  final references = counted;
  if (references == null || !context.mounted) return;

  Future<void> delete() => runQuickAction(context, () async {
    final repo = await spec.repository(ref);
    await repo.delete(id);
    spec.refresh(ref);
  });

  if (references == 0) {
    // Nothing points at it, so there is no damage to enumerate and no reason
    // to push the user towards deactivating instead.
    await confirmAndDelete(
      context,
      title: spec.deleteAction(l10n),
      message: spec.deleteConfirm(l10n, spec.label(entry)),
      confirmLabel: spec.deleteAction(l10n),
      action: () async {
        final repo = await spec.repository(ref);
        await repo.delete(id);
        spec.refresh(ref);
      },
    );
    return;
  }

  final blocked = spec.deleteBlockedWhenInUse;
  // An already-inactive entry has nothing left to offer here — deactivating it
  // again is a no-op, so that route is simply not shown.
  final canDeactivate = spec.active(entry);

  final choice = await showDialog<DestructiveChoice>(
    context: context,
    builder: (ctx) => DestructiveDialog(
      title: spec.deleteAction(l10n),
      intro: l10n.codelistInUseIntro(spec.label(entry)),
      bullets: [
        (spec.inUse(l10n, references), true),
        (
          blocked
              ? l10n.codelistDeleteBlockedInUse
              : l10n.codelistDeleteBlanksReference,
          false,
        ),
        if (canDeactivate) (l10n.codelistDeactivateKeepsHistory, false),
      ],
      confirmLabel: blocked ? null : l10n.codelistDeleteAnywayAction,
      alternativeLabel: canDeactivate ? l10n.codelistDeactivateAction : null,
      // Nothing irreversible is on offer when the server would refuse it.
      closingNote: blocked ? null : l10n.animalDeleteIrreversible,
    ),
  );
  if (!context.mounted) return;

  switch (choice) {
    case null:
    case DestructiveChoice.cancel:
      return;
    case DestructiveChoice.confirm:
      await delete();
    case DestructiveChoice.alternative:
      await runQuickAction(context, () async {
        final repo = await spec.repository(ref);
        await repo.update(id, {'active': false});
        spec.refresh(ref);
      });
  }
}
