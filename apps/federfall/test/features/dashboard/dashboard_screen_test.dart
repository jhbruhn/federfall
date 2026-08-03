import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/features/cases/cases_browser.dart';
import 'package:federfall/features/cases/pending_case_query.dart';
import 'package:federfall/features/dashboard/dashboard_providers.dart';
import 'package:federfall/features/dashboard/dashboard_screen.dart';
import 'package:federfall/features/worklist/worklist_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
// `Finder` here is flutter_test's, so hide the models' unrelated PII record of
// the same name (the mirror image of the usual clash — see CLAUDE.md).
import 'package:federfall_models/federfall_models.dart' hide Finder;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

AppUser _user(String id, {String? name, UserRole role = UserRole.carer}) =>
    AppUser(
      id: id,
      email: '$id@example.org',
      name: name,
      role: role,
      isActive: true,
    );

Future<void> _pump(
  WidgetTester tester,
  DashboardSummary summary, {
  AppUser? me,
  List<CarerWorkload>? workload,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dashboardSummaryProvider.overrideWith((ref) async => summary),
        currentUserProvider.overrideWith((ref) async => me),
        carerWorkloadProvider.overrideWith((ref) async => workload ?? const []),
        worklistProvider.overrideWith((ref) async => const []),
      ],
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: DashboardScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders the caseload KPI grid', (tester) async {
    await _pump(
      tester,
      const DashboardSummary(
        activeCount: 4,
        intakesThisYear: 7,
        byStatus: {
          CaseStatus.inCare: 3,
          CaseStatus.readyForRelease: 1,
        },
        inAviaryCount: 5,
      ),
    );

    expect(find.text('Caseload'), findsOneWidget);
    expect(find.text('Active cases'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('Intakes this year'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    // The 'Ready for release' status is promoted to its own tile…
    expect(find.text('Ready for release'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    // …and aviary residents get a tile too.
    expect(find.text('In aviary'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
  });

  testWidgets('every KPI tile is tappable (deep-link to a filtered view)', (
    tester,
  ) async {
    await _pump(
      tester,
      const DashboardSummary(
        activeCount: 4,
        intakesThisYear: 7,
        byStatus: {CaseStatus.inCare: 3, CaseStatus.readyForRelease: 1},
        inAviaryCount: 5,
      ),
    );

    // Each of the four tiles carries a chevron affordance.
    expect(find.byIcon(Icons.chevron_right), findsNWidgets(4));
  });

  testWidgets('narrow screens lead with the all-caught-up Today card', (
    tester,
  ) async {
    await _pump(
      tester,
      const DashboardSummary(
        activeCount: 4,
        intakesThisYear: 7,
        byStatus: {},
      ),
    );

    // Today always leads (federfall-6ds): even with nothing due the phone
    // layout shows the compact "all caught up" card above the caseload.
    expect(find.text('Caseload'), findsOneWidget);
    expect(find.text("Nothing due — you're all caught up."), findsOneWidget);
  });

  testWidgets('wide screens show Today beside the caseload', (tester) async {
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pump(
      tester,
      const DashboardSummary(
        activeCount: 4,
        intakesThisYear: 7,
        byStatus: {},
      ),
    );

    // Two columns: the caseload and the Today preview (here its empty-state
    // card, shown so the column isn't blank) are visible at once.
    expect(find.text('Caseload'), findsOneWidget);
    expect(find.text("Nothing due — you're all caught up."), findsOneWidget);
  });

  group('carer workload card (federfall-9mit)', () {
    const summary = DashboardSummary(
      activeCount: 4,
      intakesThisYear: 7,
      byStatus: {},
    );

    testWidgets('is hidden from a carer', (tester) async {
      await _pump(
        tester,
        summary,
        me: _user('me'),
        workload: [
          CarerWorkload(user: _user('anna', name: 'Anna'), openCases: 3),
        ],
      );

      // A carer reads only their own cases plus what was shared with them, so
      // the same figures would be a misleading fragment.
      expect(find.text('Carer workload'), findsNothing);
      expect(find.text('Anna'), findsNothing);
    });

    testWidgets('lists each carer with their open caseload for a coordinator', (
      tester,
    ) async {
      await _pump(
        tester,
        summary,
        me: _user('me', role: UserRole.coordinator),
        workload: [
          CarerWorkload(user: _user('anna', name: 'Anna'), openCases: 3),
          CarerWorkload(user: _user('bert', name: 'Bert'), openCases: 0),
        ],
      );

      // Scoped to the card: the KPI grid above it shows counts of its own.
      Finder inCard(String text) => find.descendant(
        of: find.byType(BreakdownCard),
        matching: find.text(text),
      );

      expect(find.text('Carer workload'), findsOneWidget);
      expect(inCard('Anna'), findsOneWidget);
      expect(inCard('3'), findsOneWidget);
      // Someone with capacity is listed too — that is half the point.
      expect(inCard('Bert'), findsOneWidget);
      expect(inCard('0'), findsOneWidget);
      // Each row names the member's role, so a coordinator or supervisor
      // carrying cases doesn't read as a stray entry.
      expect(inCard('Carer'), findsNWidgets(2));
    });

    testWidgets('shows a supervisor an empty roster honestly', (tester) async {
      await _pump(tester, summary, me: _user('me', role: UserRole.supervisor));

      expect(find.text('Carer workload'), findsOneWidget);
      expect(find.text('No team members'), findsOneWidget);
    });

    testWidgets('a row queues a filter for that carer and switches tabs', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          dashboardSummaryProvider.overrideWith((ref) async => summary),
          currentUserProvider.overrideWith(
            (ref) async => _user('me', role: UserRole.coordinator),
          ),
          carerWorkloadProvider.overrideWith(
            (ref) async => [
              CarerWorkload(user: _user('anna', name: 'Anna'), openCases: 3),
            ],
          ),
          worklistProvider.overrideWith((ref) async => const []),
        ],
      );
      addTearDown(container.dispose);

      final router = GoRouter(
        initialLocation: '/dashboard',
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (_, _) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/cases',
            builder: (_, _) => const Scaffold(body: Text('CASES')),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The pending query auto-disposes once nothing listens, which in
      // production is the Cases tab consuming it on mount. The stub route here
      // doesn't, so hold a subscription open for the assertion below.
      container.listen(pendingCaseQueryProvider, (_, _) {});

      // The card sits below the Today preview and the KPI grid, so on the test
      // viewport it starts off-screen — scroll it in before tapping.
      await tester.ensureVisible(find.text('Anna'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Anna'));
      await tester.pumpAndSettle();

      expect(find.text('CASES'), findsOneWidget);
      final pending = container.read(pendingCaseQueryProvider);
      expect(pending?.carer, 'anna');
      // The count is of OPEN cases, so the target keeps the browser's active
      // default — otherwise the list would overshoot the number tapped.
      expect(pending?.activity, CaseActivity.active);
    });
  });
}
