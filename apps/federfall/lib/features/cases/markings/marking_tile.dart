import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/cases_labels.dart';
import 'package:federfall/features/cases/markings/marking_sheet.dart';
import 'package:federfall/features/cases/markings/markings_providers.dart';
import 'package:federfall/features/cases/timeline_item.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A marking (ring/marker/chip) as a chronology event (FED-4.10): its type,
/// code/colour, active-or-removed status, and a menu to edit, mark it removed
/// or delete it.
class MarkingTile extends ConsumerWidget {
  const MarkingTile({
    required this.marking,
    required this.caseId,
    this.canEdit = true,
    this.isLast = false,
    super.key,
  });

  final Marking marking;
  final String caseId;
  final bool canEdit;
  final bool isLast;

  Future<void> _markRemoved(BuildContext context, WidgetRef ref) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => const _RemoveDialog(),
    );
    if (reason == null) return;
    final repo = await ref.read(markingsRepositoryProvider.future);
    await repo.update(marking.id, {
      'is_active': false,
      'removed_at': DateTime.now().toUtc().toIso8601String(),
      'removed_reason': reason,
    });
    ref.invalidate(markingsForAnimalProvider(marking.animal));
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.markingDeleteTitle),
        content: Text(l10n.markingDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.actionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.markingDeleteAction),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final repo = await ref.read(markingsRepositoryProvider.future);
    await repo.delete(marking.id);
    ref.invalidate(markingsForAnimalProvider(marking.animal));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final materialL10n = MaterialLocalizations.of(context);
    final date = marking.appliedAt ?? marking.created;

    final detail = [
      if (marking.colour case final c? when c.isNotEmpty) c,
      if (marking.code case final c? when c.isNotEmpty) c,
      if (marking.schemeOrg case final s? when s.isNotEmpty) s,
    ].join(' · ');

    return TimelineItem(
      icon: Icons.sell_outlined,
      date: formatEventDate(materialL10n, date),
      isLast: isLast,
      trailing: canEdit
          ? PopupMenuButton<void>(
              icon: const Icon(Icons.more_vert),
              iconSize: 20,
              padding: EdgeInsets.zero,
              tooltip: l10n.markingMenuTooltip,
              itemBuilder: (context) => [
                PopupMenuItem(
                  onTap: () => showMarkingSheet(
                    context,
                    animalId: marking.animal,
                    caseId: caseId,
                    marking: marking,
                  ),
                  child: Text(l10n.markingEditAction),
                ),
                if (marking.isActive)
                  PopupMenuItem(
                    onTap: () => _markRemoved(context, ref),
                    child: Text(l10n.markingRemoveAction),
                  ),
                PopupMenuItem(
                  onTap: () => _delete(context, ref),
                  child: Text(l10n.markingDeleteAction),
                ),
              ],
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            markingTypeLabel(l10n, marking.type),
            style: theme.textTheme.bodyLarge,
          ),
          if (detail.isNotEmpty)
            Text(
              detail,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          const SizedBox(height: AppSpacing.xs),
          if (!marking.isActive)
            Text(
              marking.removedAt == null
                  ? l10n.markingRemoved
                  : l10n.markingRemovedOn(
                      materialL10n.formatMediumDate(marking.removedAt!),
                    ),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}

/// Dialog asking for the reason a marking is being removed; returns the reason
/// (possibly empty) on confirm, or null on cancel.
class _RemoveDialog extends StatefulWidget {
  const _RemoveDialog();

  @override
  State<_RemoveDialog> createState() => _RemoveDialogState();
}

class _RemoveDialogState extends State<_RemoveDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.markingRemoveTitle),
      content: AppTextField(
        controller: _controller,
        label: l10n.markingRemoveReason,
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(_controller.text.trim()),
          child: Text(l10n.markingRemoveAction),
        ),
      ],
    );
  }
}
