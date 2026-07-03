import 'package:federfall/features/cases/cases_browser.dart';
import 'package:federfall/features/cases/pending_case_query.dart';
import 'package:federfall/features/home/account_menu.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
class NavShell extends ConsumerWidget {
  const NavShell({required this.navigationShell, super.key});

  /// The branch navigator state provided by [StatefulShellRoute].
  final StatefulNavigationShell navigationShell;

  /// Branch index of the Cases tab (order matches the shell's branches:
  /// dashboard, cases, animals, aviaries).
  static const _casesBranch = 1;

  void _go(WidgetRef ref, int index, {required bool compact}) {
    // Entering the Cases tab from the nav menu always gives a clean default
    // view: queue the default filter so any filter a KPI deep-link applied (or
    // one set by hand) is reset. A KPI tap navigates directly (not via here),
    // so its own queued filter is unaffected.
    if (index == _casesBranch) {
      ref.read(pendingCaseQueryProvider.notifier).queue(const CaseQuery());
    }
    navigationShell.goBranch(
      index,
      // Re-tapping the active tab returns it to its root. On compact widths,
      // also reset when *switching* tabs: the bottom bar is hidden on a detail
      // (isDetailLocation), so the only way a branch is left parked on a detail
      // is a cross-branch go() — e.g. tapping a case from an animal's detail
      // leaves the animals branch on /animals/:id. Without this, tapping that
      // tab would restore the stale detail full-screen with no bottom bar,
      // stranding the user on a screen with only the app-bar back to escape.
      // The list's scroll/filter state is keyed (federfall-8bh2) so it survives
      // the pop; there's nothing to preserve by keeping the detail.
      initialLocation: compact || index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              onDestinationSelected: (i) => _go(ref, i, compact: false),
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
            Expanded(child: navigationShell),
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
      body: navigationShell,
      bottomNavigationBar: showBottomBar
          ? NavigationBar(
              selectedIndex: navigationShell.currentIndex,
              onDestinationSelected: (i) => _go(ref, i, compact: true),
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
