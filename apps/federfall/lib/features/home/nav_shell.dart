import 'package:federfall/core/connectivity/offline_banner.dart';
import 'package:federfall/features/home/account_menu.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Adaptive top-level navigation shell (FED-7.0).
///
/// Renders a Material [NavigationBar] along the bottom on [WindowSizeClass]
/// compact screens and a [NavigationRail] alongside the content from
/// [WindowSizeClass.medium] up (extended on [WindowSizeClass.expanded]). Each
/// destination is a [StatefulShellBranch] so tab state survives switching.
/// Per-tab app bars (with the shared profile/admin actions) live on the branch
/// screens.
///
/// On compact widths the bottom bar is dropped while an item-detail page is
/// open (see [isDetailLocation]) so a phone detail stays full-screen — the
/// detail now resolves inside the shell to enable the two-pane layouts that
/// the wider widths use.
class NavShell extends StatelessWidget {
  const NavShell({required this.navigationShell, super.key});

  /// The branch navigator state provided by [StatefulShellRoute].
  final StatefulNavigationShell navigationShell;

  void _go(int index) => navigationShell.goBranch(
    index,
    // Re-tapping the active tab returns it to its initial route.
    initialLocation: index == navigationShell.currentIndex,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final destinations = [
      (
        icon: Icons.dashboard_outlined,
        selectedIcon: Icons.dashboard,
        label: l10n.navDashboard,
      ),
      (
        icon: Icons.medical_information_outlined,
        selectedIcon: Icons.medical_information,
        label: l10n.navCases,
      ),
      (
        icon: Icons.pets_outlined,
        selectedIcon: Icons.pets,
        label: l10n.navAnimals,
      ),
      (
        icon: Icons.holiday_village_outlined,
        selectedIcon: Icons.holiday_village,
        label: l10n.navAviaries,
      ),
    ];
    final sizeClass = context.windowSizeClass;

    if (sizeClass != WindowSizeClass.compact) {
      final extended = sizeClass.isExpanded;
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              extended: extended,
              selectedIndex: navigationShell.currentIndex,
              onDestinationSelected: _go,
              labelType: extended
                  ? NavigationRailLabelType.none
                  : NavigationRailLabelType.all,
              // The account / profile / admin actions live here (not in each
              // pane's app bar) whenever the rail is shown — listed directly
              // since the rail has room, and bottom-aligned as recommended for
              // rail trailing widgets.
              trailing: Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: AccountRailActions(extended: extended),
                  ),
                ),
              ),
              destinations: [
                for (final d in destinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: Text(d.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: Column(
                children: [
                  const OfflineBanner(),
                  Expanded(child: navigationShell),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Compact: keep a phone detail full-screen by dropping the bottom bar while
    // a detail page is open. `GoRouterState.of` makes this rebuild on each
    // navigation.
    final location = GoRouterState.of(context).uri.toString();
    final showBottomBar = !isDetailLocation(location);

    return Scaffold(
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(child: navigationShell),
        ],
      ),
      bottomNavigationBar: showBottomBar
          ? NavigationBar(
              selectedIndex: navigationShell.currentIndex,
              onDestinationSelected: _go,
              destinations: [
                for (final d in destinations)
                  NavigationDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: d.label,
                  ),
              ],
            )
          : null,
    );
  }
}
