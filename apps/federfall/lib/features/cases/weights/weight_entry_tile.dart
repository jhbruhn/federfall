import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/auth/roles.dart';
import 'package:federfall/core/error/quick_action.dart';
import 'package:federfall/data/repository_providers.dart';
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
        ref.invalidate(caseBundleProvider(caseId));
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
    final canDelete = weightDeletableBy(weight, me);

    return TimelineItem(
      icon: Icons.monitor_weight_outlined,
      date: formatEventDate(materialL10n, date),
      isLast: isLast,
      trailing: canEdit
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
