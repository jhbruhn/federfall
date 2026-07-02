import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/auth/roles.dart';
import 'package:federfall/core/error/quick_action.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/admin/medication_route_codelist_sheet.dart';
import 'package:federfall/features/cases/medications/medication_routes_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Supervisor-only medication-route code-list editor: maintain the org's
/// routes of administration. Re-checks the role so a typed-in URL degrades
/// gracefully — the server rules remain the real boundary.
class MedicationRoutesAdminScreen extends ConsumerWidget {
  const MedicationRoutesAdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final role = ref.watch(currentUserProvider).value?.role;

    if (!canManageTeam(role)) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.medicationRoutesAdminTitle)),
        body: EmptyView(
          icon: Icons.lock_outline,
          message: l10n.errorUnauthorized,
        ),
      );
    }

    final routes = ref.watch(medicationRoutesProvider);

    return Scaffold(
      appBar: AppBar(
        // No up arrow when shown as the right pane of the admin two-pane.
        automaticallyImplyLeading: !context.isExpanded,
        title: Text(l10n.medicationRoutesAdminTitle),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final changed = await showMedicationRouteCodelistSheet(context);
          if (changed ?? false) ref.invalidate(medicationRoutesProvider);
        },
        icon: const Icon(Icons.add),
        label: Text(l10n.medicationRouteCodelistNewTitle),
      ),
      body: AsyncValueView<List<MedicationRoute>>(
        value: routes,
        onRetry: () => ref.invalidate(medicationRoutesProvider),
        data: (list) => list.isEmpty
            ? EmptyView(
                icon: Icons.medication_outlined,
                message: l10n.medicationRoutesAdminEmpty,
              )
            : ContentBounds(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 88),
                  children: [
                    for (final r in list) _MedicationRouteTile(route: r),
                  ],
                ),
              ),
      ),
    );
  }
}

class _MedicationRouteTile extends ConsumerWidget {
  const _MedicationRouteTile({required this.route});

  final MedicationRoute route;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.medicationRouteCodelistDeleteAction),
        content: Text(l10n.medicationRouteCodelistDeleteConfirm(route.label)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.actionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.medicationRouteCodelistDeleteAction),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await runQuickAction(context, () async {
      final repo = await ref.read(medicationRoutesRepositoryProvider.future);
      await repo.delete(route.id);
      ref.invalidate(medicationRoutesProvider);
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final inactive = !route.active;

    return ListTile(
      leading: Icon(
        Icons.label_outline,
        color: inactive ? theme.colorScheme.outline : null,
      ),
      title: Text(
        route.label,
        style: inactive
            ? TextStyle(color: theme.colorScheme.onSurfaceVariant)
            : null,
      ),
      subtitle: inactive ? Text(l10n.conditionInactiveBadge) : null,
      onTap: () async {
        final changed = await showMedicationRouteCodelistSheet(
          context,
          route: route,
        );
        if (changed ?? false) ref.invalidate(medicationRoutesProvider);
      },
      trailing: PopupMenuButton<void>(
        icon: const Icon(Icons.more_vert),
        itemBuilder: (_) => [
          PopupMenuItem(
            onTap: () => _delete(context, ref),
            child: Text(l10n.medicationRouteCodelistDeleteAction),
          ),
        ],
      ),
    );
  }
}
