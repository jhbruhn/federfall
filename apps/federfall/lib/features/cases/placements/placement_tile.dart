import 'package:federfall/core/error/quick_action.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/features/cases/placements/placement_sheet.dart';
import 'package:federfall/features/cases/placements/placements_providers.dart';
import 'package:federfall/features/cases/timeline_item.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A placement / handoff as a chronology event (FED-4.9): a move to an
/// enclosure and/or a transfer of the active carer, with the holder resolved
/// to a name and an edit/delete menu.
class PlacementTile extends ConsumerWidget {
  const PlacementTile({
    required this.placement,
    required this.medicalCase,
    this.canEdit = true,
    this.isLast = false,
    super.key,
  });

  final Placement placement;
  final Case medicalCase;
  final bool canEdit;
  final bool isLast;

  Future<void> _delete(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return confirmAndDelete(
      context,
      title: l10n.placementDeleteTitle,
      message: l10n.placementDeleteConfirm,
      confirmLabel: l10n.placementDeleteAction,
      action: () async {
        final repo = await ref.read(placementsRepositoryProvider.future);
        await repo.delete(placement.id);
        ref.invalidate(caseBundleProvider(medicalCase.id));
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final materialL10n = MaterialLocalizations.of(context);
    final byId = ref.watch(orgMembersByIdProvider).value ?? const {};
    final date = placement.movedInAt ?? placement.created;

    String? nameOf(String? id) {
      if (id == null) return null;
      final u = byId[id];
      return u == null ? null : memberLabel(u);
    }

    final isHandoff = placement.toUser != null;
    final toName = nameOf(placement.toUser);
    final title = isHandoff && toName != null
        ? l10n.placementHandedOffTo(toName)
        : l10n.placementMoved;

    final location = [
      if (placement.enclosure case final e? when e.isNotEmpty) e,
      if (placement.whereHolding case final w? when w.isNotEmpty) w,
      if (placement.area case final a? when a.isNotEmpty) a,
    ].join(' · ');

    return TimelineItem(
      icon: isHandoff ? Icons.swap_horiz : Icons.move_down_outlined,
      date: formatEventDate(materialL10n, date),
      isLast: isLast,
      trailing: canEdit
          ? TimelineEntryMenu(
              editLabel: l10n.placementEditAction,
              tooltip: l10n.placementMenuTooltip,
              onEdit: () => showPlacementSheet(
                context,
                medicalCase: medicalCase,
                placement: placement,
              ),
              deleteLabel: l10n.placementDeleteAction,
              onDelete: () => _delete(context, ref),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.bodyLarge),
          if (location.isNotEmpty)
            Text(
              location,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          if (placement.conditionAtHandoff case final c? when c.isNotEmpty)
            Text(c, style: theme.textTheme.bodyMedium),
          if (placement.comments case final c? when c.isNotEmpty)
            Text(c, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
