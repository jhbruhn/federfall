import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/auth/roles.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/routing/app_routes.dart';
import 'package:federfall/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Management hub (federfall-dri): one home for the org's admin and reporting
/// surfaces, replacing the scattered app-bar icons and the team-screen gear
/// popup. Lists the team roster, organisation settings, the condition
/// code-list and reporting — each its own route.
///
/// Supervisor-gated; re-checks the role so a typed-in URL degrades gracefully.
/// The real boundary remains the server API rules.
class ManagementScreen extends ConsumerWidget {
  const ManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final role = ref.watch(currentUserProvider).value?.role;

    if (!canManageTeam(role)) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.adminTitle)),
        body: EmptyView(
          icon: Icons.lock_outline,
          message: l10n.errorUnauthorized,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.adminTitle)),
      body: ListView(
        children: [
          _HubTile(
            icon: Icons.group_outlined,
            title: l10n.manageTeamTitle,
            route: AppRoutes.manageTeam,
          ),
          _HubTile(
            icon: Icons.business_outlined,
            title: l10n.orgSettingsTitle,
            route: AppRoutes.orgSettings,
          ),
          _HubTile(
            icon: Icons.checklist_outlined,
            title: l10n.conditionsAdminTitle,
            route: AppRoutes.conditionsAdmin,
          ),
          _HubTile(
            icon: Icons.bar_chart_outlined,
            title: l10n.statsTitle,
            route: AppRoutes.statistics,
          ),
        ],
      ),
    );
  }
}

/// One hub row: a labelled icon that pushes its destination route.
class _HubTile extends StatelessWidget {
  const _HubTile({
    required this.icon,
    required this.title,
    required this.route,
  });

  final IconData icon;
  final String title;
  final String route;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon),
    title: Text(title),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => context.push(route),
  );
}
