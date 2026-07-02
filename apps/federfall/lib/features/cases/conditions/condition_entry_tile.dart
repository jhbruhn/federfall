import 'package:federfall/core/error/quick_action.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/cases_labels.dart';
import 'package:federfall/features/cases/conditions/condition_entry_sheet.dart';
import 'package:federfall/features/cases/conditions/conditions_providers.dart';
import 'package:federfall/features/cases/timeline_item.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One diagnosis as a chronology event (FED-4.5): a [TimelineItem] showing the
/// condition label (resolved from the code list, or free text), a certainty
/// chip, a notifiable badge when applicable, optional notes and resolved date,
/// and an edit/delete menu.
class ConditionEntryTile extends ConsumerWidget {
  const ConditionEntryTile({
    required this.entry,
    required this.caseId,
    this.canEdit = true,
    this.isLast = false,
    super.key,
  });

  final CaseCondition entry;
  final String caseId;
  final bool canEdit;
  final bool isLast;

  Future<void> _edit(BuildContext context, Condition? code) =>
      showConditionEntrySheet(
        context,
        caseId: caseId,
        entry: entry,
        initialLabel: code?.label,
      );

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.conditionDeleteTitle),
        content: Text(l10n.conditionDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.actionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.conditionDeleteAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    await runQuickAction(context, () async {
      final repo = await ref.read(caseConditionsRepositoryProvider.future);
      await repo.delete(entry.id);
      ref.invalidate(caseConditionsForCaseProvider(caseId));
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final materialL10n = MaterialLocalizations.of(context);

    final byId = ref.watch(conditionsByIdProvider).value ?? const {};
    final code = entry.condition == null ? null : byId[entry.condition];
    final label = code?.label ?? entry.freeText ?? '—';
    final date = entry.onsetDate ?? entry.created;
    final notes = entry.notes;

    return TimelineItem(
      icon: Icons.coronavirus_outlined,
      date: formatEventDate(materialL10n, date),
      isLast: isLast,
      trailing: canEdit
          ? PopupMenuButton<void>(
              icon: const Icon(Icons.more_vert),
              iconSize: 20,
              padding: EdgeInsets.zero,
              tooltip: l10n.conditionEditAction,
              itemBuilder: (context) => [
                PopupMenuItem(
                  onTap: () => _edit(context, code),
                  child: Text(l10n.conditionEditAction),
                ),
                PopupMenuItem(
                  onTap: () => _delete(context, ref),
                  child: Text(l10n.conditionDeleteAction),
                ),
              ],
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.bodyLarge),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (entry.certainty case final c?)
                _Tag(label: certaintyLabel(l10n, c)),
              if (code?.isNotifiable ?? false)
                _Tag(
                  label: l10n.conditionNotifiable,
                  color: theme.colorScheme.errorContainer,
                  onColor: theme.colorScheme.onErrorContainer,
                ),
              if (entry.resolvedDate case final r?)
                Text(
                  l10n.conditionResolvedOn(materialL10n.formatMediumDate(r)),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
            ],
          ),
          if (notes != null && notes.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(notes, style: theme.textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}

/// A small rounded tag (certainty / notifiable).
class _Tag extends StatelessWidget {
  const _Tag({required this.label, this.color, this.onColor});

  final String label;
  final Color? color;
  final Color? onColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = color ?? theme.colorScheme.secondaryContainer;
    final fg = onColor ?? theme.colorScheme.onSecondaryContainer;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(color: fg),
      ),
    );
  }
}
