import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/auth/roles.dart';
import 'package:federfall/core/error/quick_action.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/admin/marking_type_codelist_sheet.dart';
import 'package:federfall/features/cases/markings/marking_types_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Supervisor-only marking-type code-list editor: maintain the org's marking
/// vocabulary (ring kinds, microchip, temporary markers…). Re-checks the role
/// so a typed-in URL degrades gracefully — the server rules remain the real
/// boundary.
class MarkingTypesAdminScreen extends ConsumerWidget {
  const MarkingTypesAdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final role = ref.watch(currentUserProvider).value?.role;

    if (!canManageTeam(role)) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.markingTypesAdminTitle)),
        body: EmptyView(
          icon: Icons.lock_outline,
          message: l10n.errorUnauthorized,
        ),
      );
    }

    final types = ref.watch(markingTypesProvider);

    return Scaffold(
      appBar: AppBar(
        // No up arrow when shown as the right pane of the admin two-pane.
        automaticallyImplyLeading: !context.isExpanded,
        title: Text(l10n.markingTypesAdminTitle),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final changed = await showMarkingTypeCodelistSheet(context);
          if (changed ?? false) ref.invalidate(markingTypesProvider);
        },
        icon: const Icon(Icons.add),
        label: Text(l10n.markingTypeCodelistNewTitle),
      ),
      body: AsyncValueView<List<MarkingType>>(
        value: types,
        onRetry: () => ref.invalidate(markingTypesProvider),
        data: (list) => list.isEmpty
            ? EmptyView(
                icon: Icons.sell_outlined,
                message: l10n.markingTypesAdminEmpty,
              )
            : ContentBounds(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 88),
                  children: [
                    for (final t in list) _MarkingTypeTile(markingType: t),
                  ],
                ),
              ),
      ),
    );
  }
}

class _MarkingTypeTile extends ConsumerWidget {
  const _MarkingTypeTile({required this.markingType});

  final MarkingType markingType;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.markingTypeCodelistDeleteAction),
        content: Text(
          l10n.markingTypeCodelistDeleteConfirm(markingType.label),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.actionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.markingTypeCodelistDeleteAction),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await runQuickAction(context, () async {
      final repo = await ref.read(markingTypesRepositoryProvider.future);
      await repo.delete(markingType.id);
      ref.invalidate(markingTypesProvider);
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final inactive = !markingType.active;

    return ListTile(
      leading: Icon(
        Icons.sell_outlined,
        color: inactive ? theme.colorScheme.outline : null,
      ),
      title: Text(
        markingType.label,
        style: inactive
            ? TextStyle(color: theme.colorScheme.onSurfaceVariant)
            : null,
      ),
      subtitle: inactive ? Text(l10n.conditionInactiveBadge) : null,
      onTap: () async {
        final changed = await showMarkingTypeCodelistSheet(
          context,
          markingType: markingType,
        );
        if (changed ?? false) ref.invalidate(markingTypesProvider);
      },
      trailing: PopupMenuButton<void>(
        icon: const Icon(Icons.more_vert),
        itemBuilder: (_) => [
          PopupMenuItem(
            onTap: () => _delete(context, ref),
            child: Text(l10n.markingTypeCodelistDeleteAction),
          ),
        ],
      ),
    );
  }
}
