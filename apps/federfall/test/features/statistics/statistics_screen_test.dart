import 'dart:async';

import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/cases_browser.dart';
import 'package:federfall/features/cases/pending_case_query.dart';
import 'package:federfall/features/statistics/intake_map_providers.dart';
import 'package:federfall/features/statistics/statistics_providers.dart';
import 'package:federfall/features/statistics/statistics_screen.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:mocktail/mocktail.dart';

class MockCaseReportRowsRepo extends Mock
    implements PbCaseReportRowsRepository {}

Future<void> _pump(
  WidgetTester tester,
  Statistics stats, {
  UserRole role = UserRole.coordinator,
  List<IntakeLocation> locations = const [],
  PbCaseReportRowsRepository? reportRows,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        statisticsProvider.overrideWith((ref) async => stats),
        if (reportRows != null)
          caseReportRowsRepositoryProvider.overrideWith(
            (ref) async => reportRows,
          ),
        // The statistics screen's intake-map preview card loads through the
        // real repositories otherwise, which need network — stub it out so
        // this test stays focused on the KPI/breakdown figures.
        intakeLocationsProvider.overrideWith(
          (ref, admittedRange) async => locations,
        ),
        currentUserProvider.overrideWith(
          (ref) async =>
              AppUser(id: 'u1', email: 'me@x.org', role: role, org: 'org1'),
        ),
      ],
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: StatisticsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Gives the screen a surface tall enough for the KPI grid, the intake-map
/// preview card AND all three breakdowns — otherwise the breakdowns sit below
/// the default viewport and the lazy `ListView` never builds them.
void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

const Statistics _emptyStats = Statistics(
  totalCases: 0,
  openCases: 0,
  outcomes: [],
  bySpecies: [],
  byCondition: [],
  avgTimeInCareDays: null,
);

void main() {
  testWidgets('renders KPIs and outcome/species/condition breakdowns', (
    tester,
  ) async {
    _useTallSurface(tester);

    await _pump(
      tester,
      const Statistics(
        totalCases: 12,
        openCases: 4,
        outcomes: [
          OutcomeStat(DispositionType.released, 5),
          OutcomeStat(DispositionType.died, 3),
        ],
        bySpecies: [StatCount('Columba livia', 9)],
        byCondition: [StatCount('Trichomoniasis', 6)],
        avgTimeInCareDays: 15.4,
      ),
    );

    expect(find.text('12'), findsOneWidget); // total cases
    expect(find.text('15.4 d'), findsOneWidget); // avg time in care
    expect(find.text('Released'), findsOneWidget);
    expect(find.text('Columba livia'), findsOneWidget);
    expect(find.text('Trichomoniasis'), findsOneWidget);
  });

  testWidgets('shows an empty hint for breakdowns with no data', (
    tester,
  ) async {
    _useTallSurface(tester);

    await _pump(tester, _emptyStats);

    expect(find.text('Not enough data yet'), findsWidgets);
    expect(find.text('–'), findsOneWidget); // avg with no data
  });

  testWidgets('the intake-map card is a tappable summary with a chevron', (
    tester,
  ) async {
    await _pump(tester, _emptyStats);

    expect(find.text('Intake map'), findsOneWidget);
    expect(find.text('No mapped intakes'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
  });

  testWidgets('the intake-map preview thumbnail carries tile attribution', (
    tester,
  ) async {
    // federfall-fq3c: the tile provider's usage policy wants attribution on
    // every rendered map, thumbnails included — linking through to the
    // attributed intake map screen is not a substitute.
    await _pump(
      tester,
      _emptyStats,
      locations: const [
        IntakeLocation(caseId: 'c1', point: LatLng(53.14, 8.21)),
      ],
    );

    expect(find.byType(MapAttribution), findsOneWidget);
  });

  testWidgets('a breakdown row hands the Cases tab its filter', (
    tester,
  ) async {
    // federfall-5puj: a number the user can't ask "which ones?" about is a
    // dead end, and the dashboard KPIs already set the pattern.
    _useTallSurface(tester);

    final container = ProviderContainer(
      overrides: [
        statisticsProvider.overrideWith(
          (ref) async => const Statistics(
            totalCases: 3,
            openCases: 1,
            outcomes: [OutcomeStat(DispositionType.euthanized, 2)],
            bySpecies: [],
            byCondition: [StatCount('Katzenbiss', 3)],
            avgTimeInCareDays: null,
          ),
        ),
        intakeLocationsProvider.overrideWith(
          (ref, admittedRange) async => const <IntakeLocation>[],
        ),
        currentUserProvider.overrideWith(
          (ref) async => const AppUser(
            id: 'u1',
            email: 'me@x.org',
            role: UserRole.coordinator,
            org: 'org1',
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final router = GoRouter(
      initialLocation: '/statistics',
      routes: [
        GoRoute(
          path: '/statistics',
          builder: (_, _) => const StatisticsScreen(),
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

    // The pending query is auto-disposed once nothing listens to it, which in
    // production is the Cases tab consuming it on mount. The stub route here
    // doesn't, so hold a subscription open for the assertion below.
    container.listen(pendingCaseQueryProvider, (_, _) {});

    await tester.tap(find.text('Katzenbiss'));
    await tester.pumpAndSettle();

    expect(find.text('CASES'), findsOneWidget);
    final query = container.read(pendingCaseQueryProvider);
    expect(query?.condition, 'Katzenbiss');
    // The figures are org-wide and count closed cases, so the list must be
    // widened past the browser's "my active cases" default to match them.
    expect(query?.allScope, isTrue);
    expect(query?.activity, CaseActivity.all);
  });

  testWidgets('the unknown-outcome bucket is the one row with no way in', (
    tester,
  ) async {
    _useTallSurface(tester);

    await _pump(
      tester,
      const Statistics(
        totalCases: 2,
        openCases: 0,
        // A disposition carrying a wire value this build does not know: it can
        // be counted, but no filter value names it.
        outcomes: [
          OutcomeStat(DispositionType.released, 1),
          OutcomeStat(null, 1),
        ],
        bySpecies: [],
        byCondition: [],
        avgTimeInCareDays: null,
      ),
    );

    expect(find.text('Released'), findsOneWidget);
    expect(find.text('Unknown outcome'), findsOneWidget);
    // One chevron for 'Released', none for the unknown bucket. (The intake-map
    // card carries the other.)
    expect(find.byIcon(Icons.chevron_right), findsNWidgets(2));
  });

  testWidgets('the CSV export shows an inline spinner while it loads', (
    tester,
  ) async {
    // federfall-80tc: the export button now swaps its icon for a spinner like
    // the case-report share/print buttons do, and it reads ONE pre-joined row
    // set instead of three whole collections.
    final repo = MockCaseReportRowsRepo();
    final pending = Completer<List<CaseReportRow>>();
    when(repo.all).thenAnswer((_) => pending.future);

    await _pump(tester, _emptyStats, reportRows: repo);
    await tester.tap(find.byIcon(Icons.download_outlined));
    await tester.pump();

    expect(find.byIcon(Icons.download_outlined), findsNothing);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );

    // Nothing to export: the snackbar says so and the icon comes back — no
    // share sheet, so this stays clear of the platform channel.
    pending.complete(const []);
    await tester.pumpAndSettle();

    expect(find.text('No cases to export'), findsOneWidget);
    expect(find.byIcon(Icons.download_outlined), findsOneWidget);
    verify(repo.all).called(1);
  });

  testWidgets('a carer gets the unauthorized view, not the figures', (
    tester,
  ) async {
    await _pump(tester, _emptyStats, role: UserRole.carer);

    expect(find.text('You are not authorized to do that'), findsOneWidget);
    expect(find.byIcon(Icons.download_outlined), findsNothing);
    expect(find.text('Intake map'), findsNothing);
  });
}
