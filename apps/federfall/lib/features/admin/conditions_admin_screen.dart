import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/auth/roles.dart';
import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/admin/condition_codelist_sheet.dart';
import 'package:federfall/features/cases/conditions/conditions_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Supervisor-only condition code-list editor (UX Phase A): maintain the org's
/// diagnosis vocabulary. Re-checks the role so a typed-in URL degrades
/// gracefully — the server rules remain the real boundary.
class ConditionsAdminScreen extends ConsumerWidget {
  const ConditionsAdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final role = ref.watch(currentUserProvider).value?.role;

    if (!canManageTeam(role)) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.conditionsAdminTitle)),
        body: EmptyView(
          icon: Icons.lock_outline,
          message: l10n.errorUnauthorized,
        ),
      );
    }

    final conditions = ref.watch(conditionsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.conditionsAdminTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final changed = await showConditionCodelistSheet(context);
          if (changed ?? false) ref.invalidate(conditionsProvider);
        },
        icon: const Icon(Icons.add),
        label: Text(l10n.conditionCodelistNewTitle),
      ),
      body: AsyncValueView<List<Condition>>(
        value: conditions,
        onRetry: () => ref.invalidate(conditionsProvider),
        errorMessage: (e) => errorMessage(l10n, e),
        data: (list) => list.isEmpty
            ? EmptyView(
                icon: Icons.checklist_outlined,
                message: l10n.conditionsAdminEmpty,
              )
            : ListView(
                padding: const EdgeInsets.only(bottom: 88),
                children: [
                  for (final c in list)
                    _ConditionTile(condition: c),
                ],
              ),
      ),
    );
  }
}

class _ConditionTile extends ConsumerWidget {
  const _ConditionTile({required this.condition});

  final Condition condition;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.conditionCodelistDeleteAction),
        content: Text(l10n.conditionCodelistDeleteConfirm(condition.label)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.actionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.conditionCodelistDeleteAction),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final repo = await ref.read(conditionsRepositoryProvider.future);
    await repo.delete(condition.id);
    ref.invalidate(conditionsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final inactive = !condition.active;
    final badges = [
      if (condition.isNotifiable) l10n.conditionNotifiableLabel,
      if (inactive) l10n.conditionInactiveBadge,
    ];

    return ListTile(
      leading: Icon(
        Icons.label_outline,
        color: inactive ? theme.colorScheme.outline : null,
      ),
      title: Text(
        condition.label,
        style: inactive
            ? TextStyle(color: theme.colorScheme.onSurfaceVariant)
            : null,
      ),
      subtitle: badges.isEmpty ? null : Text(badges.join(' · ')),
      onTap: () async {
        final changed = await showConditionCodelistSheet(
          context,
          condition: condition,
        );
        if (changed ?? false) ref.invalidate(conditionsProvider);
      },
      trailing: PopupMenuButton<void>(
        icon: const Icon(Icons.more_vert),
        itemBuilder: (_) => [
          PopupMenuItem(
            onTap: () => _delete(context, ref),
            child: Text(l10n.conditionCodelistDeleteAction),
          ),
        ],
      ),
    );
  }
}
