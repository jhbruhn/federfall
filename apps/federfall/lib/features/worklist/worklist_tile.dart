import 'package:federfall/core/error/quick_action.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/medications/administration_sheet.dart';
import 'package:federfall/features/worklist/worklist.dart';
import 'package:federfall/features/worklist/worklist_labels.dart';
import 'package:federfall/features/worklist/worklist_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/routing/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// One worklist row: kind icon, case number, and a relative detail line that
/// turns error-coloured when overdue. Taps through to the case. A medication
/// due gets a "log dose" shortcut that opens the administration sheet prefilled
/// from the prescription — the carer still confirms the details and saves.
class WorklistTile extends ConsumerWidget {
  const WorklistTile({
    required this.item,
    required this.now,
    this.onTap,
    this.selected = false,
    super.key,
  });

  final WorklistItem item;
  final DateTime now;

  /// Overrides the default tap behaviour (deep-link to the case). Supplied by
  /// the wide-screen Today layout to drive its side detail pane instead.
  final VoidCallback? onTap;

  /// Highlighted when its case is open in the adjacent pane (two-pane).
  final bool selected;

  Future<void> _logDose(BuildContext context, WidgetRef ref) async {
    final saved = await showAdministrationSheet(
      context,
      caseId: item.caseId,
      plan: item.medication,
    );
    if (!(saved ?? false) || !context.mounted) return;
    ref.invalidate(worklistSourceProvider);
  }

  Future<void> _markFollowUpDone(BuildContext context, WidgetRef ref) =>
      runQuickAction(context, () async {
        final repo = await ref.read(followUpsRepositoryProvider.future);
        await repo.update(item.followUp!.id, {
          'done_at': DateTime.now().toUtc().toIso8601String(),
        });
        if (!context.mounted) return;
        ref.invalidate(worklistSourceProvider);
      });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final overdue = item.severity == WorklistSeverity.overdue;

    return ListTile(
      selected: selected,
      leading: Icon(worklistIcon(item.kind)),
      title: Text(worklistItemTitle(l10n, item)),
      subtitle: Text(
        worklistItemDetail(l10n, item, now),
        style: overdue
            ? theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              )
            : null,
      ),
      trailing: _trailing(context, ref, l10n),
      onTap: onTap ?? () => context.go(AppRoutes.caseDetail(item.caseId)),
    );
  }

  /// A one-tap completion shortcut where the kind supports it (log a dose, mark
  /// a recheck done); a plain chevron otherwise.
  Widget _trailing(BuildContext context, WidgetRef ref, AppLocalizations l10n) {
    if (item.kind == WorklistKind.medicationDue && item.medication != null) {
      return IconButton(
        icon: const Icon(Icons.vaccines_outlined),
        tooltip: l10n.worklistLogDose,
        onPressed: () => _logDose(context, ref),
      );
    }
    if (item.kind == WorklistKind.followUpDue && item.followUp != null) {
      return IconButton(
        icon: const Icon(Icons.check_circle_outline),
        tooltip: l10n.followUpMarkDone,
        onPressed: () => _markFollowUpDone(context, ref),
      );
    }
    return const Icon(Icons.chevron_right);
  }
}
