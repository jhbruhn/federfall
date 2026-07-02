import 'package:federfall/core/error/quick_action.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/quarantine/quarantine_providers.dart';
import 'package:federfall/features/cases/quarantine/quarantine_sheet.dart';
import 'package:federfall/features/cases/timeline_item.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which end of a quarantine period a tile renders. One [Quarantine] record
/// shows as two timeline entries: its [started] imposition (at `set_at`) and,
/// once the end date has passed, a separate [ended] marker (at `until`).
enum QuarantinePhase { started, ended }

/// One end of a quarantine period as a chronology event (federfall-uvm). The
/// [QuarantinePhase.started] tile carries the period detail, the reason, the
/// edit/delete menu and the inline "end now" shortcut; the
/// [QuarantinePhase.ended] tile is a plain marker at the date it lapsed.
class QuarantineTile extends ConsumerWidget {
  const QuarantineTile({
    required this.entry,
    required this.caseId,
    this.phase = QuarantinePhase.started,
    this.canEdit = true,
    this.isCurrent = false,
    this.isLast = false,
    super.key,
  });

  final Quarantine entry;
  final String caseId;
  final QuarantinePhase phase;
  final bool canEdit;

  /// Whether this is the case's active quarantine (the latest record). Only the
  /// current one offers the inline "end now" shortcut.
  final bool isCurrent;
  final bool isLast;

  Future<void> _edit(BuildContext context) =>
      showQuarantineSheet(context, caseId: caseId, entry: entry);

  Future<void> _endNow(BuildContext context, WidgetRef ref) =>
      runQuickAction(context, () async {
        final repo = await ref.read(quarantineRepositoryProvider.future);
        await repo.update(entry.id, {
          'quarantine_until': DateTime.now().toUtc().toIso8601String(),
        });
        ref
          ..invalidate(quarantineForCaseProvider(caseId))
          ..invalidate(caseQuarantineUntilProvider);
      });

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
    if (confirmed != true || !context.mounted) return;

    await runQuickAction(context, () async {
      final repo = await ref.read(quarantineRepositoryProvider.future);
      await repo.delete(entry.id);
      ref
        ..invalidate(quarantineForCaseProvider(caseId))
        ..invalidate(caseQuarantineUntilProvider);
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final materialL10n = MaterialLocalizations.of(context);

    // The "ended" entry is a plain marker at the date quarantine lapsed.
    if (phase == QuarantinePhase.ended) {
      return TimelineItem(
        icon: Icons.health_and_safety_outlined,
        date: formatEventDate(materialL10n, entry.until ?? entry.created),
        isLast: isLast,
        child: Text(
          l10n.quarantineEndedEvent,
          style: theme.textTheme.bodyLarge,
        ),
      );
    }

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
          if (reason != null && reason.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(reason, style: theme.textTheme.bodyMedium),
          ],
          // Quick "end now" shortcut on the active quarantine (mirrors the
          // medication "log dose" button) — sets the end to today.
          if (isCurrent && canEdit && !ended)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  onPressed: () => _endNow(context, ref),
                  icon: const Icon(Icons.event_busy_outlined, size: 18),
                  label: Text(l10n.quarantineEndNowAction),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
