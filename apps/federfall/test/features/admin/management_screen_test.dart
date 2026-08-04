import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/features/admin/management_screen.dart';
import 'package:federfall/features/admin/org_settings_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/routing/app_routes.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Future<void> _pump(WidgetTester tester, {required UserRole role}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWith(
          (ref) async => AppUser(id: 'u1', email: 'me@x.org', role: role),
        ),
      ],
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ManagementScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _wide(WidgetTester tester) {
  tester.view.physicalSize = const Size(1100, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Mirrors how the app's router declares the hub: the sections are CHILD routes
/// of `/admin`, which is what puts the hub page beneath a directly-opened
/// section URL and so gives it a real back button.
GoRouter _router({required String initialLocation}) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    GoRoute(
      path: AppRoutes.home,
      builder: (_, _) => const Scaffold(body: Text('HOME')),
    ),
    GoRoute(
      path: AppRoutes.admin,
      builder: (_, _) => const ManagementScreen(),
      routes: [
        for (final section in AdminSection.values)
          GoRoute(
            path: section.segment,
            builder: (_, _) => ManagementScreen(section: section),
          ),
      ],
    ),
  ],
);

Future<GoRouter> _pumpRouted(
  WidgetTester tester, {
  required String initialLocation,
}) async {
  final router = _router(initialLocation: initialLocation);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWith(
          (ref) async => const AppUser(
            id: 'u1',
            email: 'me@x.org',
            role: UserRole.supervisor,
            org: 'org1',
          ),
        ),
        currentOrganisationProvider.overrideWith(
          (ref) async => const Organisation(id: 'org1', name: 'Pigeon Aid'),
        ),
      ],
      child: MaterialApp.router(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

/// What the *address bar* shows: `routerDelegate.currentConfiguration.uri` is
/// what go_router reports to the platform, so asserting on it (rather than the
/// laxer [GoRouter.state]) is what actually pins the URL being correct. The two
/// disagree after an imperative push, which is the bug these tests guard.
String _location(GoRouter router) =>
    router.routerDelegate.currentConfiguration.uri.toString();

void main() {
  testWidgets('a carer is shown an unauthorized message', (tester) async {
    await _pump(tester, role: UserRole.carer);
    expect(find.text('You are not authorized to do that'), findsOneWidget);
  });

  testWidgets('a supervisor sees every management entry', (tester) async {
    await _pump(tester, role: UserRole.supervisor);
    expect(find.text('Team'), findsOneWidget);
    expect(find.text('Organisation settings'), findsOneWidget);
    expect(find.text('Condition code-list'), findsOneWidget);
    // Statistics is reached from the account menu / rail, not the hub.
    expect(find.text('Statistics'), findsNothing);
  });

  group('the hub is grouped, and every entry says what it governs', () {
    test('the grouped walk covers every section exactly once', () {
      // The hub renders group by group, so a section whose group forgot it
      // would silently vanish from the menu while its route kept working.
      expect(
        AdminSectionGroup.values.expand((g) => g.sections),
        AdminSection.values,
      );
    });

    testWidgets('each group heads its own entries, each with a subtitle', (
      tester,
    ) async {
      // Tall enough that the whole menu is laid out at once, and narrow enough
      // (< 840) that the hub owns the full width rather than a 360 pane.
      tester.view.physicalSize = const Size(700, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _pump(tester, role: UserRole.supervisor);

      final l10n = AppLocalizations.of(
        tester.element(find.byType(ManagementScreen)),
      );
      for (final group in AdminSectionGroup.values) {
        expect(
          find.text(group.title(l10n)),
          findsOneWidget,
          reason: 'group heading ${group.name}',
        );
        for (final section in group.sections) {
          expect(
            find.text(section.title(l10n)),
            findsOneWidget,
            reason: 'title of ${section.name}',
          );
          expect(
            find.text(section.subtitle(l10n)),
            findsOneWidget,
            reason: 'subtitle of ${section.name}',
          );
        }
      }
    });
  });

  testWidgets('wide screens show the hub beside a selection placeholder', (
    tester,
  ) async {
    _wide(tester);

    await _pump(tester, role: UserRole.supervisor);

    // Hub on the left, empty-selection placeholder on the right, and the
    // persistent app bar (which carries the back-to-app affordance) on top —
    // the hub stays a single screen, so that affordance never disappears.
    expect(find.text('Team'), findsOneWidget);
    expect(find.text('Select a section to manage'), findsOneWidget);
    expect(find.text('Administration'), findsOneWidget);
  });

  group('every section is a real, linkable location', () {
    testWidgets('a section segment composes into its absolute route', (
      tester,
    ) async {
      for (final section in AdminSection.values) {
        expect(section.route, '${AppRoutes.admin}/${section.segment}');
      }
    });

    testWidgets('opening a section URL directly still leads back to the hub', (
      tester,
    ) async {
      final router = await _pumpRouted(
        tester,
        initialLocation: AppRoutes.orgSettings,
      );

      // Narrow: the section owns the screen, and the hub page sits beneath it,
      // so the implied back arrow is there and returns to the hub instead of
      // stranding the user on a dead end.
      expect(find.text('Pigeon Aid'), findsOneWidget);
      expect(find.text('Administration'), findsNothing);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.text('Administration'), findsOneWidget);
      expect(_location(router), AppRoutes.admin);
    });

    testWidgets('a section URL opens the hub two-pane on wide screens', (
      tester,
    ) async {
      _wide(tester);
      await _pumpRouted(tester, initialLocation: AppRoutes.orgSettings);

      // The section is the right pane and the hub is still the left one — a
      // link into a section is not a different screen from clicking to it.
      expect(find.text('Administration'), findsOneWidget);
      expect(find.text('Pigeon Aid'), findsOneWidget);
      expect(find.text('Select a section to manage'), findsNothing);
    });

    testWidgets('picking a section puts it in the URL', (tester) async {
      _wide(tester);
      final router = await _pumpRouted(
        tester,
        initialLocation: AppRoutes.admin,
      );
      expect(_location(router), AppRoutes.admin);

      await tester.tap(find.text('Organisation settings'));
      await tester.pumpAndSettle();

      // The address bar tracks the pane, so the section can be linked and
      // survives a reload.
      expect(_location(router), AppRoutes.orgSettings);
      expect(find.text('Pigeon Aid'), findsOneWidget);
    });

    testWidgets('moving between sections does not stack pages', (tester) async {
      _wide(tester);
      final router = await _pumpRouted(
        tester,
        initialLocation: AppRoutes.admin,
      );

      await tester.tap(find.text('Organisation settings'));
      await tester.pumpAndSettle();
      expect(router.routerDelegate.currentConfiguration.matches, hasLength(2));

      // Only the routing is asserted past this point, so settle by pumping a
      // fixed span: TeamScreen's own providers are not stubbed here and its
      // spinner would keep pumpAndSettle from ever returning.
      await tester.tap(find.text('Team'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // Still the hub + one section, not a third page: `go` to a sibling swaps
      // the child rather than piling section history up behind the pane.
      expect(_location(router), AppRoutes.manageTeam);
      expect(router.routerDelegate.currentConfiguration.matches, hasLength(2));
    });

    testWidgets('the hub back arrow leaves administration in one press', (
      tester,
    ) async {
      _wide(tester);
      final router = await _pumpRouted(
        tester,
        initialLocation: AppRoutes.orgSettings,
      );

      // A plain pop would land on the hub with an empty right pane, which reads
      // as nothing having happened — the hub is on screen either way. So the
      // arrow beside "Administration" exits instead of deselecting, even though
      // there IS a page to pop.
      expect(router.canPop(), isTrue);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.text('HOME'), findsOneWidget);
      expect(_location(router), AppRoutes.home);
    });

    testWidgets('a cold-opened hub is not a dead end', (tester) async {
      final router = await _pumpRouted(
        tester,
        initialLocation: AppRoutes.admin,
      );

      // Nothing beneath the hub to pop, so the implied arrow would have
      // vanished and left no way back into the app.
      expect(router.canPop(), isFalse);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.text('HOME'), findsOneWidget);
      expect(_location(router), AppRoutes.home);
    });
  });
}
