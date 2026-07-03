import 'package:federfall/core/error/quick_action.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/features/cases/follow_ups/follow_up_sheet.dart';
import 'package:federfall/features/cases/timeline_item.dart';
import 'package:federfall/features/worklist/worklist_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One recheck as a chronology event (cr3.4): a [TimelineItem] on its due date,
/// showing the note, a "done" chip once carried out, and a menu to edit, mark
/// done / reopen, or delete.
class FollowUpTile extends ConsumerWidget {
  const FollowUpTile({
    required this.followUp,
    required this.caseId,
    this.canEdit = true,
    this.isLast = false,
    super.key,
  });

  final FollowUp followUp;
  final String caseId;
  final bool canEdit;
  final bool isLast;

  Future<void> _toggleDone(BuildContext context, WidgetRef ref) =>
      runQuickAction(context, () async {
        final repo = await ref.read(followUpsRepositoryProvider.future);
        await repo.update(followUp.id, {
          'done_at': followUp.doneAt == null
              ? DateTime.now().toUtc().toIso8601String()
              : '',
        });
        ref
          ..invalidate(caseBundleProvider(caseId))
          ..invalidate(worklistSourceProvider);
      });

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.followUpDeleteTitle),
        content: Text(l10n.followUpDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.actionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.followUpDeleteAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await runQuickAction(context, () async {
      final repo = await ref.read(followUpsRepositoryProvider.future);
      await repo.delete(followUp.id);
      ref
        ..invalidate(caseBundleProvider(caseId))
        ..invalidate(worklistSourceProvider);
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final materialL10n = MaterialLocalizations.of(context);
    final due = followUp.dueAt ?? followUp.created;
    final done = followUp.doneAt != null;
    final overdue =
        !done &&
        due != null &&
        due.toLocal().isBefore(DateUtils.dateOnly(DateTime.now()));

    return TimelineItem(
      icon: done ? Icons.event_available_outlined : Icons.event_repeat_outlined,
      date: formatEventDate(materialL10n, due),
      isLast: isLast,
      trailing: canEdit
          ? _Menu(
              done: done,
              onEdit: () => showFollowUpSheet(
                context,
                caseId: caseId,
                followUp: followUp,
              ),
              onToggleDone: () => _toggleDone(context, ref),
              onDelete: () => _delete(context, ref),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            followUp.note?.isNotEmpty ?? false
                ? followUp.note!
                : l10n.followUpDefaultLabel,
            style: theme.textTheme.bodyLarge,
          ),
          if (done)
            _Chip(
              label: l10n.followUpDone,
              color: theme.colorScheme.secondaryContainer,
              onColor: theme.colorScheme.onSecondaryContainer,
            )
          else if (overdue)
            _Chip(
              label: l10n.worklistOverdueDays(
                DateUtils.dateOnly(
                  DateTime.now(),
                ).difference(DateUtils.dateOnly(due.toLocal())).inDays,
              ),
              color: theme.colorScheme.errorContainer,
              onColor: theme.colorScheme.onErrorContainer,
            ),
        ],
      ),
    );
  }
}

class _Menu extends StatelessWidget {
  const _Menu({
    required this.done,
    required this.onEdit,
    required this.onToggleDone,
    required this.onDelete,
  });

  final bool done;
  final VoidCallback onEdit;
  final VoidCallback onToggleDone;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return PopupMenuButton<void>(
      icon: const Icon(Icons.more_vert),
      iconSize: 20,
      padding: EdgeInsets.zero,
      tooltip: l10n.followUpEditAction,
      itemBuilder: (context) => [
        PopupMenuItem(onTap: onEdit, child: Text(l10n.followUpEditAction)),
        PopupMenuItem(
          onTap: onToggleDone,
          child: Text(done ? l10n.followUpReopen : l10n.followUpMarkDone),
        ),
        PopupMenuItem(onTap: onDelete, child: Text(l10n.followUpDeleteAction)),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.color,
    required this.onColor,
  });

  final String label;
  final Color color;
  final Color onColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 4,
        ),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(color: onColor),
        ),
      ),
    );
  }
}
