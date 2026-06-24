import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/auth/roles.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/routing/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The single account menu shown on every top-level destination
/// (federfall-dri). Collapses what used to be a row of bare app-bar icons
/// (admin, profile) plus the dashboard-only stats icon into one avatar button,
/// so the chrome stays identical across tabs and there is one home for future
/// cross-cutting entries.
///
/// Items are role-gated: reporting for coordinators/supervisors, the
/// management hub for supervisors. Profile is always present. The gate mirrors
/// the server access rules so users aren't offered actions they can't perform;
/// it is not the security boundary itself.
class AccountMenu extends ConsumerWidget {
  const AccountMenu({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final role = ref.watch(currentUserProvider).value?.role;

    return PopupMenuButton<String>(
      icon: const Icon(Icons.account_circle_outlined),
      tooltip: l10n.accountTooltip,
      onSelected: context.push,
      itemBuilder: (_) => [
        _item(
          AppRoutes.profile,
          Icons.account_circle_outlined,
          l10n.profileTitle,
        ),
        if (canViewReports(role))
          _item(
            AppRoutes.statistics,
            Icons.bar_chart_outlined,
            l10n.statsTitle,
          ),
        if (canManageTeam(role))
          _item(
            AppRoutes.admin,
            Icons.manage_accounts_outlined,
            l10n.adminTitle,
          ),
      ],
    );
  }

  /// One menu row: leading icon + label, valued by its destination route.
  PopupMenuItem<String> _item(String route, IconData icon, String label) =>
      PopupMenuItem<String>(
        value: route,
        child: Row(
          children: [
            Icon(icon),
            const SizedBox(width: 12),
            Text(label),
          ],
        ),
      );
}
