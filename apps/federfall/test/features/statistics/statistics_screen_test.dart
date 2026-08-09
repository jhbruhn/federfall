import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/features/cases/cases_browser.dart';
import 'package:federfall/features/cases/pending_case_query.dart';
import 'package:federfall/features/statistics/annual_report_sheet.dart';
import 'package:federfall/features/statistics/intake_map_providers.dart';
import 'package:federfall/features/statistics/intake_series_chart.dart';
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

Future<void> _pump(
  WidgetTester tester,
  OrgStatistics stats, {
  UserRole role = UserRole.coordinator,
  List<IntakeLocation> locations = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        statisticsProvider.overrideWith((ref, year) async => stats),
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
/// preview card AND all three breakdowns — each of which now carries a donut
/// above its rows — otherwise the lower cards sit below the viewport and the
/// lazy `ListView` never builds them.
void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

const OrgStatistics _emptyStats = OrgStatistics();

/// Pins the period so a test can assert what the screen does with one.
class _FixedPeriod extends StatisticsPeriod {
  _FixedPeriod(this._period);

  final StatsPeriod _period;

  @override
  StatsPeriod build() => _period;
}

void main() {
  testWidgets('renders KPIs and outcome/species/condition breakdowns', (
    tester,
  ) async {
    _useTallSurface(tester);

    await _pump(
      tester,
      const OrgStatistics(
        intakes: 12,
        closed: 8,
        inCare: 4,
        outcomes: [
          OutcomeStat(DispositionType.released, 5),
          OutcomeStat(DispositionType.died, 3),
        ],
        bySpecies: [StatCount('Columba livia', 9)],
        byCondition: [StatCount('Trichomoniasis', 6)],
        avgTimeInCareDays: 15.4,
        releaseRate: 0.625,
        mortalityRate: 0.375,
      ),
    );

    expect(find.text('12'), findsOneWidget); // intakes
    expect(find.text('15.4 d'), findsOneWidget); // avg time in care
    expect(find.text('Released'), findsOneWidget);
    expect(find.text('Columba livia'), findsOneWidget);
    // A diagnosis is named twice: once on its bar, once on the row under it.
    expect(find.text('Trichomoniasis'), findsNWidgets(2));
    // And the bar is a share of the INTAKES (6 of 12), which the caption above
    // it says out loud — diagnoses overlap, so they are no share of each other
    // (federfall-qogh).
    expect(find.text('50%'), findsOneWidget);
    expect(find.text('Share of intakes'), findsOneWidget);
  });

  testWidgets('rates are shares of the cases that ended, and say so', (
    tester,
  ) async {
    // federfall-nmwi: the number a rehab is actually asked for is the share
    // released of the cases that REACHED an outcome — over intakes it would
    // sag every time admissions rise. The denominator is on screen for the
    // same reason.
    _useTallSurface(tester);

    await _pump(
      tester,
      const OrgStatistics(
        intakes: 12,
        closed: 8,
        inCare: 4,
        releaseRate: 0.625,
        mortalityRate: 0.375,
      ),
    );

    expect(find.text('63 %'), findsOneWidget);
    expect(find.text('38 %'), findsOneWidget);
    expect(find.text('Rates over 8 ended cases'), findsOneWidget);
  });

  testWidgets('an undefined rate is an em dash, not 0 %', (tester) async {
    _useTallSurface(tester);

    await _pump(tester, const OrgStatistics(intakes: 3, inCare: 3));

    // Avg time in care and both rates: nothing has ended, so none of the three
    // is defined. Claiming a 0 % release rate would be a different statement.
    expect(find.text('–'), findsNWidgets(3));
    expect(
      find.text('No case has ended in this period yet'),
      findsOneWidget,
    );
  });

  testWidgets('intakes over time draws a bar per bucket with the prior year', (
    tester,
  ) async {
    _useTallSurface(tester);

    await _pump(
      tester,
      const OrgStatistics(
        year: 2026,
        intakes: 3,
        series: IntakeSeries(
          kind: SeriesBucket.month,
          points: [IntakePoint(1, 2), IntakePoint(2, 1)],
          previousYear: 2025,
          previousPoints: [IntakePoint(1, 5), IntakePoint(2, 0)],
        ),
      ),
    );

    expect(find.text('Intakes over time'), findsOneWidget);
    expect(find.byType(IntakeSeriesChart), findsOneWidget);
    // The legend names both years, so a bar's colour is readable as a period.
    expect(find.text('2026'), findsWidgets);
    expect(find.text('2025'), findsWidgets);
  });

  testWidgets('shows an empty hint for breakdowns with no data', (
    tester,
  ) async {
    _useTallSurface(tester);

    await _pump(tester, _emptyStats);

    expect(find.text('Not enough data yet'), findsWidgets);
  });

  testWidgets('the intake-map card is a tappable summary with a chevron', (
    tester,
  ) async {
    _useTallSurface(tester);
    await _pump(tester, _emptyStats);

    expect(find.text('Intake map'), findsOneWidget);
    expect(find.text('No mapped intakes'), findsOneWidget);
    // Two ways in: the intakes KPI and this card.
    expect(find.byIcon(Icons.chevron_right), findsNWidgets(2));
  });

  testWidgets('the intake-map preview thumbnail carries tile attribution', (
    tester,
  ) async {
    // federfall-fq3c: the tile provider's usage policy wants attribution on
    // every rendered map, thumbnails included — linking through to the
    // attributed intake map screen is not a substitute.
    _useTallSurface(tester);
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
          (ref, year) async => const OrgStatistics(
            year: 2026,
            intakes: 3,
            closed: 2,
            inCare: 1,
            outcomes: [OutcomeStat(DispositionType.euthanized, 2)],
            byCondition: [StatCount('Katzenbiss', 3)],
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

    // The chart names it too; the tappable one is the row beneath it.
    await tester.tap(find.text('Katzenbiss').last);
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
      const OrgStatistics(
        intakes: 2,
        closed: 2,
        // A disposition carrying a wire value this build does not know: it can
        // be counted, but no filter value names it.
        outcomes: [
          OutcomeStat(DispositionType.released, 1),
          OutcomeStat(null, 1),
        ],
      ),
    );

    expect(find.text('Released'), findsOneWidget);
    expect(find.text('Unknown outcome'), findsOneWidget);
    // One chevron for 'Released', none for the unknown bucket. (The intakes
    // KPI and the intake-map card carry the other two.)
    expect(find.byIcon(Icons.chevron_right), findsNWidgets(3));
  });

  testWidgets('a month period narrows the tap-through to that month', (
    tester,
  ) async {
    _useTallSurface(tester);

    final container = ProviderContainer(
      overrides: [
        statisticsPeriodProvider.overrideWith(
          () => _FixedPeriod(const StatsPeriod(year: 2026, month: 3)),
        ),
        statisticsProvider.overrideWith(
          (ref, args) async => const OrgStatistics(
            year: 2026,
            month: 3,
            intakes: 4,
            bySpecies: [StatCount('Stadttaube', 4)],
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
    container.listen(pendingCaseQueryProvider, (_, _) {});

    await tester.tap(find.text('Stadttaube').first);
    await tester.pumpAndSettle();

    final range = container.read(pendingCaseQueryProvider)?.admittedRange;
    // The whole of March 2026 and nothing either side of it: a list that
    // spilled into April would not match the figure that was tapped.
    expect(range?.start, DateTime(2026, 3));
    expect(range?.end.month, 3);
    expect(range?.end.day, 31);
  });

  testWidgets('a wide window reads two cards at a time, a narrow one stacks', (
    tester,
  ) async {
    // Desktop and web get the width; the phone layout is unchanged. Keyed on
    // the available width rather than on the platform, so a resized window
    // reflows without anything else knowing about it.
    const stats = OrgStatistics(
      intakes: 4,
      closed: 2,
      series: IntakeSeries(
        kind: SeriesBucket.month,
        points: [IntakePoint(1, 3), IntakePoint(2, 1)],
      ),
      outcomes: [OutcomeStat(DispositionType.released, 2)],
      bySpecies: [StatCount('Stadttaube', 4)],
      byCondition: [StatCount('Trichomoniasis', 1)],
    );

    tester.view.physicalSize = const Size(1400, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pump(tester, stats);

    final outcomes = find.ancestor(
      of: find.text('Outcomes'),
      matching: find.byType(BreakdownCard),
    );
    final map = find
        .ancestor(
          of: find.text('Intake map'),
          matching: find.byType(Card),
        )
        .first;
    // The head of each column sits beside the other: different x, same y.
    expect(tester.getTopLeft(map).dx, lessThan(tester.getTopLeft(outcomes).dx));
    expect(tester.getTopLeft(map).dy, tester.getTopLeft(outcomes).dy);

    // The series keeps the full width either way — 31 day-bars in half a
    // window is a comb.
    final chartWidth = tester.getSize(find.byType(IntakeSeriesChart)).width;
    expect(chartWidth, greaterThan(tester.getSize(outcomes).width));

    tester.view.physicalSize = const Size(700, 2600);
    await _pump(tester, stats);
    expect(tester.getTopLeft(map).dx, tester.getTopLeft(outcomes).dx);
  });

  testWidgets('the export action opens the annual-report sheet', (
    tester,
  ) async {
    // federfall-dk0c: the app bar no longer exports anything itself — the PDF
    // and the CSV are two renderings of one server-side report, so the action
    // opens the sheet that picks a period and a format.
    await _pump(tester, _emptyStats);
    await tester.tap(find.byIcon(Icons.download_outlined));
    await tester.pumpAndSettle();

    expect(find.byType(AnnualReportSheet), findsOneWidget);
    expect(find.text('PDF report'), findsOneWidget);
    expect(find.text('CSV table'), findsOneWidget);
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
