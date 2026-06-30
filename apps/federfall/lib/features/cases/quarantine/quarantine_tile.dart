import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/quarantine/quarantine_providers.dart';
import 'package:federfall/features/cases/quarantine/quarantine_sheet.dart';
import 'package:federfall/features/cases/timeline_item.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One quarantine period as a chronology event (federfall-uvm): a
/// [TimelineItem] showing the end date, an "ended" badge once it has passed,
/// an optional reason and an edit/delete menu.
class QuarantineTile extends ConsumerWidget {
  const QuarantineTile({
    required this.entry,
    required this.caseId,
    this.canEdit = true,
    this.isLast = false,
    super.key,
  });

  final Quarantine entry;
  final String caseId;
  final bool canEdit;
  final bool isLast;

  Future<void> _edit(BuildContext context) =>
      showQuarantineSheet(context, caseId: caseId, entry: entry);

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.quarantineDeleteTitle),
        content: Text(l10n.quarantineDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.actionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.quarantineDeleteAction),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final repo = await ref.read(quarantineRepositoryProvider.future);
    await repo.delete(entry.id);
    ref
      ..invalidate(quarantineForCaseProvider(caseId))
      ..invalidate(caseQuarantineUntilProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final materialL10n = MaterialLocalizations.of(context);

    final date = entry.setAt ?? entry.created;
    final until = entry.until;
    final ended = until != null && !until.isAfter(DateTime.now());
    final reason = entry.reason;

    return TimelineItem(
      icon: Icons.shield_outlined,
      date: formatEventDate(materialL10n, date),
      isLast: isLast,
      trailing: canEdit
          ? PopupMenuButton<void>(
              icon: const Icon(Icons.more_vert),
              iconSize: 20,
              padding: EdgeInsets.zero,
              tooltip: l10n.quarantineEditAction,
              itemBuilder: (context) => [
                PopupMenuItem(
                  onTap: () => _edit(context),
                  child: Text(l10n.quarantineEditAction),
                ),
                PopupMenuItem(
                  onTap: () => _delete(context, ref),
                  child: Text(l10n.quarantineDeleteAction),
                ),
              ],
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            until == null
                ? l10n.quarantineTitle
                : l10n.quarantineTileUntil(
                    materialL10n.formatMediumDate(until),
                  ),
            style: theme.textTheme.bodyLarge,
          ),
          if (ended) ...[
            const SizedBox(height: AppSpacing.xs),
            _Tag(label: l10n.caseQuarantineEnded),
          ],
          if (reason != null && reason.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(reason, style: theme.textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}

/// A small rounded tag (the "ended" badge).
class _Tag extends StatelessWidget {
  const _Tag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}
