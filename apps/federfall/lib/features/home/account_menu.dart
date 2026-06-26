import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/auth/roles.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/routing/app_routes.dart';
import 'package:federfall/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The single account menu shown on every top-level destination
/// (federfall-dri). Collapses what used to be a row of bare app-bar icons
/// (admin, profile) plus the dashboard-only stats icon into one avatar button,
/// so the chrome stays identical across tabs and there is one home for future
/// cross-cutting entries.
///
/// App-bar placement: visible only on compact widths. Wider layouts show a
/// navigation rail whose trailing area lists the same entries directly (see
/// [AccountRailActions]) — the rail has room, so no popup is needed — and
/// keeping the menu in each pane's app bar too would duplicate it (and feel out
/// of place in a narrow list pane). So this self-hides once the rail appears.
class AccountMenu extends StatelessWidget {
  const AccountMenu({super.key});

  @override
  Widget build(BuildContext context) {
    if (context.windowSizeClass != WindowSizeClass.compact) {
      return const SizedBox.shrink();
    }
    return const AccountMenuButton();
  }
}

/// The role-gated account popup itself: profile (always), reporting (for
/// coordinators/supervisors) and the management hub (for supervisors). The gate
/// mirrors the server access rules so users aren't offered actions they can't
/// perform; it is not the security boundary itself. Used in the app bar on
/// compact widths and in the navigation rail on wider ones.
class AccountMenuButton extends ConsumerWidget {
  const AccountMenuButton({super.key});

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

/// The account entries listed directly in the navigation rail's trailing area
/// on wider widths — the rail has room, so the actions are always visible
/// rather than tucked behind a popup. Same role-gated set as the popup
/// (profile always; reporting for coordinators/supervisors; the management hub
/// for supervisors). Adapts to the rail's [extended] state: icon + label rows
/// when extended, tooltipped icon buttons when collapsed.
class AccountRailActions extends ConsumerWidget {
  const AccountRailActions({required this.extended, super.key});

  /// Whether the host rail is extended (labels inline) or collapsed (icons).
  final bool extended;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final role = ref.watch(currentUserProvider).value?.role;

    final entries = <({String route, IconData icon, String label})>[
      (
        route: AppRoutes.profile,
        icon: Icons.account_circle_outlined,
        label: l10n.profileTitle,
      ),
      if (canViewReports(role))
        (
          route: AppRoutes.statistics,
          icon: Icons.bar_chart_outlined,
          label: l10n.statsTitle,
        ),
      if (canManageTeam(role))
        (
          route: AppRoutes.admin,
          icon: Icons.manage_accounts_outlined,
          label: l10n.adminTitle,
        ),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final e in entries)
          _RailAction(
            icon: e.icon,
            label: e.label,
            extended: extended,
            onTap: () => context.push(e.route),
          ),
      ],
    );
  }
}

/// One [AccountRailActions] entry, styled to match the rail's current density.
class _RailAction extends StatelessWidget {
  const _RailAction({
    required this.icon,
    required this.label,
    required this.extended,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool extended;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (!extended) {
      return IconButton(
        icon: Icon(icon),
        tooltip: label,
        onPressed: onTap,
      );
    }
    // The rail measures its trailing with an unbounded width (to derive its own
    // intrinsic width), so the row must shrink-wrap — no flex children.
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon),
            const SizedBox(width: AppSpacing.md),
            Text(label),
          ],
        ),
      ),
    );
  }
}
