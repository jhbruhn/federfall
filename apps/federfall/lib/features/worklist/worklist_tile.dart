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
  const WorklistTile({required this.item, required this.now, super.key});

  final WorklistItem item;
  final DateTime now;

  Future<void> _logDose(BuildContext context, WidgetRef ref) async {
    final saved = await showAdministrationSheet(
      context,
      caseId: item.caseId,
      plan: item.medication,
    );
    if (saved ?? false) ref.invalidate(worklistProvider);
  }

  Future<void> _markFollowUpDone(WidgetRef ref) async {
    final repo = await ref.read(followUpsRepositoryProvider.future);
    await repo.update(item.followUp!.id, {
      'done_at': DateTime.now().toUtc().toIso8601String(),
    });
    ref.invalidate(worklistProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final overdue = item.severity == WorklistSeverity.overdue;

    return ListTile(
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
      onTap: () => context.go(AppRoutes.caseDetail(item.caseId)),
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
        onPressed: () => _markFollowUpDone(ref),
      );
    }
    return const Icon(Icons.chevron_right);
  }
}
