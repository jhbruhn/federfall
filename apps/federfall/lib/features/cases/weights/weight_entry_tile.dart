import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/auth/roles.dart';
import 'package:federfall/core/error/quick_action.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/animals/custody_providers.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/features/cases/timeline_item.dart';
import 'package:federfall/features/cases/weights/weight_entry_sheet.dart';
import 'package:federfall/features/cases/weights/weights_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One weight measurement as a chronology event (FED-4.4): a [TimelineItem]
/// showing the measured weight, its date, an optional note and an edit/delete
/// menu. Delete only appears for the weight's author or a supervisor,
/// mirroring the server rule (federfall-tha).
///
/// Since 1700000079 a weight is only writable by whoever holds the BIRD, which
/// is not the same question as [canEdit]: the active carer of a *disposed* case
/// may still write its journal while the bird has moved on, so the menu needs
/// both. [weightDeletableBy] answers only the author half and is ANDed with
/// custody here for the same reason.
///
/// [caseId] is the case whose chronology is showing this weight, and is null on
/// the animal's own weight history. A weight is animal-scoped — `case` is
/// optional on it and frozen after create — so one taken outside any case
/// appears in no case timeline at all, and the animal screen is the only place
/// it can be corrected.
class WeightEntryTile extends ConsumerWidget {
  const WeightEntryTile({
    required this.weight,
    this.caseId,
    this.canEdit = true,
    this.isLast = false,
    super.key,
  });

  final Weight weight;
  final String? caseId;
  final bool canEdit;
  final bool isLast;

  Future<void> _edit(BuildContext context) => showWeightEntrySheet(
    context,
    animalId: weight.animal,
    caseId: caseId,
    weight: weight,
  );

  Future<void> _delete(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return confirmAndDelete(
      context,
      title: l10n.weightDeleteTitle,
      message: l10n.weightDeleteConfirm,
      confirmLabel: l10n.weightDeleteAction,
      action: () async {
        final repo = await ref.read(weightsRepositoryProvider.future);
        await repo.delete(weight.id);
        // Both views, the same way the sheet's own save does: the animal's
        // life-long history always, the case chronology only when this tile
        // is standing in one.
        ref.invalidate(weightsForAnimalProvider(weight.animal));
        if (caseId case final id?) ref.invalidate(caseBundleProvider(id));
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final materialL10n = MaterialLocalizations.of(context);
    final date = weight.measuredAt ?? weight.created;
    final notes = weight.notes;
    final me = ref.watch(currentUserProvider).value;
    final holdsBird =
        ref.watch(canWriteAnimalProvider(weight.animal)).value ?? false;
    final canDelete = holdsBird && weightDeletableBy(weight, me);

    return TimelineItem(
      icon: Icons.monitor_weight_outlined,
      date: formatLocalDate(materialL10n, date),
      isLast: isLast,
      trailing: canEdit && holdsBird
          ? TimelineEntryMenu(
              editLabel: l10n.weightEditAction,
              onEdit: () => _edit(context),
              deleteLabel: l10n.weightDeleteAction,
              onDelete: canDelete ? () => _delete(context, ref) : null,
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.weightEventLabel(formatWeightG(l10n, weight.weightG)),
            style: theme.textTheme.bodyLarge,
          ),
          if (notes != null && notes.isNotEmpty)
            Text(notes, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
