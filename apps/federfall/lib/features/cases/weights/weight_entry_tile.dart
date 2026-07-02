import 'package:federfall/core/error/quick_action.dart';
import 'package:federfall/data/repository_providers.dart';
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
/// menu.
class WeightEntryTile extends ConsumerWidget {
  const WeightEntryTile({
    required this.weight,
    required this.caseId,
    this.canEdit = true,
    this.isLast = false,
    super.key,
  });

  final Weight weight;
  final String caseId;
  final bool canEdit;
  final bool isLast;

  Future<void> _edit(BuildContext context) => showWeightEntrySheet(
    context,
    animalId: weight.animal,
    caseId: caseId,
    weight: weight,
  );

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.weightDeleteTitle),
        content: Text(l10n.weightDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.actionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.weightDeleteAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    await runQuickAction(context, () async {
      final repo = await ref.read(weightsRepositoryProvider.future);
      await repo.delete(weight.id);
      ref.invalidate(weightsForCaseProvider(caseId));
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final materialL10n = MaterialLocalizations.of(context);
    final date = weight.measuredAt ?? weight.created;
    final notes = weight.notes;

    return TimelineItem(
      icon: Icons.monitor_weight_outlined,
      date: formatEventDate(materialL10n, date),
      isLast: isLast,
      trailing: canEdit
          ? PopupMenuButton<void>(
              icon: const Icon(Icons.more_vert),
              iconSize: 20,
              padding: EdgeInsets.zero,
              tooltip: l10n.weightEditAction,
              itemBuilder: (context) => [
                PopupMenuItem(
                  onTap: () => _edit(context),
                  child: Text(l10n.weightEditAction),
                ),
                PopupMenuItem(
                  onTap: () => _delete(context, ref),
                  child: Text(l10n.weightDeleteAction),
                ),
              ],
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.weightEventLabel(formatWeightG(weight.weightG)),
            style: theme.textTheme.bodyLarge,
          ),
          if (notes != null && notes.isNotEmpty)
            Text(notes, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
