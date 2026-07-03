import 'dart:async';
import 'package:federfall/core/auth/auth_status.dart';
import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/server/server_config.dart';
import 'package:federfall/core/server/server_config_controller.dart';
import 'package:federfall/core/server/server_info_provider.dart';
import 'package:federfall/features/admin/management_screen.dart';
import 'package:federfall/features/auth/confirm_reset_screen.dart';
import 'package:federfall/features/auth/login_screen.dart';
import 'package:federfall/features/cases/case_detail_screen.dart';
import 'package:federfall/features/cases/cases_browser.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/features/cases/cases_screen.dart';
import 'package:federfall/features/cases/new_case_screen.dart';
import 'package:federfall/features/profile/profile_screen.dart';
import 'package:federfall/features/server_setup/setup_screen.dart';
import 'package:federfall/features/statistics/statistics_providers.dart';
import 'package:federfall/features/statistics/statistics_screen.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/routing/app_routes.dart';
import 'package:federfall/routing/router.dart';
// Hide the domain Finder model so flutter_test's Finder (used below) wins.
import 'package:federfall_models/federfall_models.dart' hide Finder;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fake that resolves to a fixed server config.
class _FakeServerConfig extends ServerConfigController {
  _FakeServerConfig(this._config);
  final ServerConfig _config;
  @override
  Future<ServerConfig> build() async => _config;
}

/// Fake that resolves to a fixed auth status.
class _FakeAuthStatus extends AuthStatus {
  _FakeAuthStatus({required this.authed});
  final bool authed;
  @override
  Future<bool> build() async => authed;
}

/// Fake auth status that can flip mid-test (sign-in happening).
class _MutableAuthStatus extends AuthStatus {
  _MutableAuthStatus({required this.initial});
  final bool initial;
  @override
  Future<bool> build() async => initial;

  void authed({required bool value}) => state = AsyncData(value);
}

Future<ProviderContainer> _pumpAt(
  WidgetTester tester, {
  required ServerConfig config,
  required bool authed,
}) {
  final container = ProviderContainer(
    overrides: [
      serverConfigControllerProvider.overrideWith(
        () => _FakeServerConfig(config),
      ),
      authStatusProvider.overrideWith(() => _FakeAuthStatus(authed: authed)),
      // Discovery is exercised in its own tests; here it just resolves so the
      // login gate doesn't reach for the network.
      serverInfoProvider.overrideWith((ref) async => null),
      casesBrowserDataProvider.overrideWith(
        (ref) async => const CasesBrowserData(
          cases: [],
          animalsById: {},
          myUserId: 'u1',
        ),
      ),
      currentUserProvider.overrideWith((ref) async => null),
    ],
  );
  return _pumpContainer(tester, container);
}

Future<ProviderContainer> _pumpContainer(
  WidgetTester tester,
  ProviderContainer container,
) async {
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: Consumer(
        builder: (context, ref, _) => MaterialApp.router(
          // Matches lib/app/view/app.dart so restoration tests behave like the
          // real app.
          restorationScopeId: 'app',
          locale: const Locale('de'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: ref.watch(routerProvider),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('unconfigured server → setup', (tester) async {
    await _pumpAt(
      tester,
      config: const ServerConfig.unconfigured(),
      authed: false,
    );
    expect(find.byType(SetupScreen), findsOneWidget);
  });

  testWidgets('configured + unauthenticated → login', (tester) async {
    await _pumpAt(
      tester,
      config: const ServerConfig.configured('https://x.example'),
      authed: false,
    );
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('configured + authenticated → cases tab', (tester) async {
    await _pumpAt(
      tester,
      config: const ServerConfig.configured('https://x.example'),
      authed: true,
    );
    expect(find.byType(CasesScreen), findsOneWidget);
  });

  testWidgets('case detail is reachable at /cases/:id', (tester) async {
    final container = ProviderContainer(
      overrides: [
        serverConfigControllerProvider.overrideWith(
          () => _FakeServerConfig(
            const ServerConfig.configured('https://x.example'),
          ),
        ),
        authStatusProvider.overrideWith(() => _FakeAuthStatus(authed: true)),
        casesBrowserDataProvider.overrideWith(
          (ref) async => const CasesBrowserData(
            cases: [],
            animalsById: {},
            myUserId: 'u1',
          ),
        ),
        currentUserProvider.overrideWith((ref) async => null),
        caseByIdProvider(
          'c1',
        ).overrideWith((ref) async => const Case(id: 'c1', animal: 'a1')),
      ],
    );
    await _pumpContainer(tester, container);

    final router = container.read(routerProvider)
      ..go(AppRoutes.caseDetail('c1'));
    await tester.pumpAndSettle();

    expect(find.byType(CaseDetailScreen), findsOneWidget);
    // The address bar must track the detail page (nested under the cases
    // branch + go, so the shell no longer owns the URL).
    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      '/cases/c1',
    );
  });

  testWidgets('a pushed /cases/browse applies the deep-linked filter', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        serverConfigControllerProvider.overrideWith(
          () => _FakeServerConfig(
            const ServerConfig.configured('https://x.example'),
          ),
        ),
        authStatusProvider.overrideWith(() => _FakeAuthStatus(authed: true)),
        casesBrowserDataProvider.overrideWith(
          (ref) async => const CasesBrowserData(
            // Owned by someone else: only visible under scope=all.
            cases: [
              Case(
                id: 'c1',
                animal: 'a1',
                caseNumber: '2026-099',
                activeCarer: 'other',
                status: CaseStatus.inCare,
              ),
            ],
            animalsById: {},
            myUserId: 'u1',
          ),
        ),
        currentUserProvider.overrideWith((ref) async => null),
      ],
    );
    await _pumpContainer(tester, container);

    unawaited(
      container
          .read(routerProvider)
          .push(AppRoutes.casesBrowse('scope=all&activity=active')),
    );
    await tester.pumpAndSettle();

    // The transient browser renders and the scope=all filter reveals the
    // other carer's case (hidden under the default "mine" scope).
    expect(find.byType(CasesScreen), findsOneWidget);
    expect(find.text('2026-099'), findsOneWidget);
  });

  testWidgets('a deep link entered before sign-in is restored after it', (
    tester,
  ) async {
    final auth = _MutableAuthStatus(initial: false);
    final container = ProviderContainer(
      overrides: [
        serverConfigControllerProvider.overrideWith(
          () => _FakeServerConfig(
            const ServerConfig.configured('https://x.example'),
          ),
        ),
        authStatusProvider.overrideWith(() => auth),
        serverInfoProvider.overrideWith((ref) async => null),
        casesBrowserDataProvider.overrideWith(
          (ref) async => const CasesBrowserData(
            cases: [],
            animalsById: {},
            myUserId: 'u1',
          ),
        ),
        currentUserProvider.overrideWith((ref) async => null),
        caseByIdProvider(
          'c1',
        ).overrideWith((ref) async => const Case(id: 'c1', animal: 'a1')),
      ],
    );
    await _pumpContainer(tester, container);

    // The shared link arrives while unauthenticated: held at the login gate,
    // with the requested location remembered.
    final router = container.read(routerProvider)
      ..go(AppRoutes.caseDetail('c1'));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(
      router.routerDelegate.currentConfiguration.uri.queryParameters['from'],
      '/cases/c1',
    );

    // Sign-in completes → the original target opens, not the default tab.
    auth.authed(value: true);
    await tester.pumpAndSettle();

    expect(find.byType(CaseDetailScreen), findsOneWidget);
    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      '/cases/c1',
    );
  });

  testWidgets('admin and statistics redirect a carer home (federfall-vxg)', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        serverConfigControllerProvider.overrideWith(
          () => _FakeServerConfig(
            const ServerConfig.configured('https://x.example'),
          ),
        ),
        authStatusProvider.overrideWith(() => _FakeAuthStatus(authed: true)),
        casesBrowserDataProvider.overrideWith(
          (ref) async => const CasesBrowserData(
            cases: [],
            animalsById: {},
            myUserId: 'u1',
          ),
        ),
        currentUserProvider.overrideWith(
          (ref) async => const AppUser(
            id: 'u1',
            email: 'carer@example.org',
            role: UserRole.carer,
          ),
        ),
      ],
    );
    await _pumpContainer(tester, container);

    final router = container.read(routerProvider)..go(AppRoutes.admin);
    await tester.pumpAndSettle();
    expect(find.byType(ManagementScreen), findsNothing);
    expect(find.byType(CasesScreen), findsOneWidget);
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      AppRoutes.home,
    );

    router.go(AppRoutes.manageTeam);
    await tester.pumpAndSettle();
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      AppRoutes.home,
    );

    router.go(AppRoutes.statistics);
    await tester.pumpAndSettle();
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      AppRoutes.home,
    );
  });

  testWidgets('a supervisor reaches the management hub', (tester) async {
    final container = ProviderContainer(
      overrides: [
        serverConfigControllerProvider.overrideWith(
          () => _FakeServerConfig(
            const ServerConfig.configured('https://x.example'),
          ),
        ),
        authStatusProvider.overrideWith(() => _FakeAuthStatus(authed: true)),
        casesBrowserDataProvider.overrideWith(
          (ref) async => const CasesBrowserData(
            cases: [],
            animalsById: {},
            myUserId: 'u1',
          ),
        ),
        currentUserProvider.overrideWith(
          (ref) async => const AppUser(
            id: 'u1',
            email: 'chef@example.org',
            role: UserRole.supervisor,
          ),
        ),
      ],
    );
    await _pumpContainer(tester, container);

    container.read(routerProvider).go(AppRoutes.admin);
    await tester.pumpAndSettle();

    expect(find.byType(ManagementScreen), findsOneWidget);
  });

  testWidgets(
    'cases list search state survives crossing the expanded breakpoint '
    '(federfall-8bh2)',
    (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pumpAt(
        tester,
        config: const ServerConfig.configured('https://x.example'),
        authed: true,
      );
      expect(find.byType(CasesScreen), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'bussard');
      await tester.pump();
      expect(find.text('bussard'), findsOneWidget);

      // Cross into the expanded two-pane layout: the list moves from the pane
      // navigator's root into the shell's left pane. The shared GlobalKey must
      // carry the mounted list (and its in-progress search) across.
      tester.view.physicalSize = const Size(1200, 800);
      await tester.pumpAndSettle();
      expect(find.byType(CasesScreen), findsOneWidget);
      expect(find.text('bussard'), findsOneWidget);

      // And back down again.
      tester.view.physicalSize = const Size(800, 600);
      await tester.pumpAndSettle();
      expect(find.text('bussard'), findsOneWidget);
    },
  );

  testWidgets('confirm-reset is reachable without a session', (tester) async {
    final container = await _pumpAt(
      tester,
      config: const ServerConfig.configured('https://x.example'),
      authed: false,
    );

    container.read(routerProvider).go('${AppRoutes.confirmReset}?token=abc');
    await tester.pumpAndSettle();

    expect(find.byType(ConfirmResetScreen), findsOneWidget);
  });

  testWidgets('a case detail restores across process death (federfall-7ev8)', (
    tester,
  ) async {
    await tester.pumpWidget(const _RestorableApp());
    await tester.pumpAndSettle();

    GoRouter.of(
      tester.element(find.byType(CasesScreen)),
    ).go(AppRoutes.caseDetail('c1'));
    await tester.pumpAndSettle();
    expect(find.byType(CaseDetailScreen), findsOneWidget);

    // Simulate Android killing and restoring the process: the container (and so
    // the GoRouter) is rebuilt from scratch inside [_RestorableApp], so only
    // go_router's state restoration can bring the detail back — not a surviving
    // in-memory router. Its route carries a restorable pageBuilder, so it must.
    await tester.restartAndRestore();
    await tester.pumpAndSettle();

    expect(find.byType(CaseDetailScreen), findsOneWidget);
  });

  testWidgets('a pushed overlay (profile) is NOT restored across process '
      'death — the shell comes back instead (federfall-7ev8)', (tester) async {
    await tester.pumpWidget(const _RestorableApp());
    await tester.pumpAndSettle();

    // Profile is reached with push, so it is an imperative match go_router
    // drops on restore (the boundary is push vs go, not builder/pageBuilder).
    unawaited(
      GoRouter.of(
        tester.element(find.byType(CasesScreen)),
      ).push(AppRoutes.profile),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ProfileScreen), findsOneWidget);

    await tester.restartAndRestore();
    await tester.pumpAndSettle();

    expect(find.byType(ProfileScreen), findsNothing);
    expect(find.byType(CasesScreen), findsOneWidget);
  });

  // Every route that must stay non-resumable is reached with push() so it is an
  // imperative match go_router drops on restore. This locks in the exclusion
  // policy that used to live in _isResumableLocation: a future push()→go() slip
  // on any of these silently reopens the stranding bug, and this fails first.
  // (casesBrowse is push-only too but renders a CasesScreen, so it has no
  // distinct widget to assert on — it rides the same mechanism.)
  for (final entry in <({String label, String route, Finder overlay})>[
    (
      label: 'the create-case form',
      route: AppRoutes.newCase,
      overlay: find.byType(NewCaseScreen),
    ),
    (
      label: 'the profile',
      route: AppRoutes.profile,
      overlay: find.byType(ProfileScreen),
    ),
    (
      label: 'the statistics screen',
      route: AppRoutes.statistics,
      overlay: find.byType(StatisticsScreen),
    ),
    (
      label: 'the management hub',
      route: AppRoutes.admin,
      overlay: find.byType(ManagementScreen),
    ),
  ]) {
    testWidgets(
      '${entry.label} is not restored across process death (federfall-7ev8)',
      (tester) async {
        await tester.pumpWidget(const _RestorableApp());
        await tester.pumpAndSettle();

        unawaited(
          GoRouter.of(
            tester.element(find.byType(Navigator).first),
          ).push(entry.route),
        );
        await tester.pumpAndSettle();
        expect(entry.overlay, findsOneWidget); // sanity: on the overlay

        await tester.restartAndRestore();
        await tester.pumpAndSettle();

        // Restore drops the imperative match: the overlay is gone and the
        // shell home is back.
        expect(entry.overlay, findsNothing);
        expect(find.byType(CasesScreen), findsWidgets);
      },
    );
  }
}

/// A minimal authenticated app whose Riverpod container — and therefore the
/// `routerProvider`'s [GoRouter] — is rebuilt from scratch when the widget tree
/// restarts. This makes `tester.restartAndRestore()` a faithful process-death
/// simulation: the previous in-memory router is gone, so anything that comes
/// back had to travel through go_router's restoration bucket.
class _RestorableApp extends StatefulWidget {
  const _RestorableApp();
  @override
  State<_RestorableApp> createState() => _RestorableAppState();
}

class _RestorableAppState extends State<_RestorableApp> {
  late final ProviderContainer container = ProviderContainer(
    overrides: [
      serverConfigControllerProvider.overrideWith(
        () => _FakeServerConfig(
          const ServerConfig.configured('https://x.example'),
        ),
      ),
      authStatusProvider.overrideWith(() => _FakeAuthStatus(authed: true)),
      serverInfoProvider.overrideWith((ref) async => null),
      casesBrowserDataProvider.overrideWith(
        (ref) async => const CasesBrowserData(
          cases: [],
          animalsById: {},
          myUserId: 'u1',
        ),
      ),
      // A supervisor so the role-gated overlays (admin, statistics) are
      // reachable in the exclusion-policy test below.
      currentUserProvider.overrideWith(
        (ref) async => const AppUser(
          id: 'u1',
          email: 'chef@example.org',
          role: UserRole.supervisor,
        ),
      ),
      caseByIdProvider(
        'c1',
      ).overrideWith((ref) async => const Case(id: 'c1', animal: 'a1')),
      // Resolve so the statistics overlay doesn't spin forever (its loading
      // indicator would never let pumpAndSettle settle).
      statisticsProvider.overrideWith(
        (ref) async => const Statistics(
          totalCases: 0,
          openCases: 0,
          outcomes: [],
          bySpecies: [],
          byCondition: [],
          avgTimeInCareDays: null,
        ),
      ),
    ],
  );

  @override
  void dispose() {
    container.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => UncontrolledProviderScope(
    container: container,
    child: Consumer(
      builder: (context, ref, _) => MaterialApp.router(
        restorationScopeId: 'app',
        locale: const Locale('de'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: ref.watch(routerProvider),
      ),
    ),
  );
}
