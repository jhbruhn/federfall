import 'package:federfall/core/connectivity/offline_banner.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Adaptive top-level navigation shell (FED-7.0).
///
/// Renders a Material [NavigationBar] along the bottom on narrow screens and a
/// [NavigationRail] alongside the content on wide/web layouts. Each destination
/// is a [StatefulShellBranch] so tab state survives switching. Per-tab app bars
/// (with the shared profile/admin actions) live on the branch screens.
class NavShell extends StatelessWidget {
  const NavShell({required this.navigationShell, super.key});

  /// The branch navigator state provided by [StatefulShellRoute].
  final StatefulNavigationShell navigationShell;

  /// Width at/above which the rail replaces the bottom bar.
  static const double _railBreakpoint = 600;

  /// Width at/above which the rail shows labels inline (extended).
  static const double _extendedRailBreakpoint = 840;

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
    final width = MediaQuery.sizeOf(context).width;

    if (width >= _railBreakpoint) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              extended: width >= _extendedRailBreakpoint,
              selectedIndex: navigationShell.currentIndex,
              onDestinationSelected: _go,
              labelType: width >= _extendedRailBreakpoint
                  ? NavigationRailLabelType.none
                  : NavigationRailLabelType.all,
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

    return Scaffold(
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(child: navigationShell),
        ],
      ),
      bottomNavigationBar: NavigationBar(
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
      ),
    );
  }
}
