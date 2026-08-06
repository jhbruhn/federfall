import 'dart:async';
import 'dart:typed_data';

import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/statistics/annual_report_sheet.dart';
import 'package:federfall/features/statistics/period_selector.dart';
import 'package:federfall/features/statistics/statistics_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockCaseReportRepo extends Mock implements PbCaseReportRepository {}

OrgStatistics _statsWithYears(List<int> years) =>
    OrgStatistics(intakeYears: years);

/// Pumps the sheet against [repo]. The sheet is pumped directly rather than
/// through `showAnnualReportSheet` — a modal route would only add a frame of
/// animation to every expectation here.
Future<void> _pump(
  WidgetTester tester,
  PbCaseReportRepository repo, {
  List<int> intakeYears = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        caseReportRepositoryProvider.overrideWith((ref) async => repo),
        statisticsProvider.overrideWith(
          (ref, year) async => _statsWithYears(intakeYears),
        ),
      ],
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: AnnualReportSheet()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Stubs the fetch with a future that never completes: these tests assert what
/// was REQUESTED, and completing it would hand bytes to the platform share
/// channel, which a widget test has no implementation for.
void _stubPending(MockCaseReportRepo repo, [Completer<Uint8List>? pending]) {
  when(
    () => repo.fetchAnnualReport(
      year: any(named: 'year'),
      csv: any(named: 'csv'),
      lang: any(named: 'lang'),
      tzOffsetMinutes: any(named: 'tzOffsetMinutes'),
    ),
  ).thenAnswer((_) => (pending ?? Completer<Uint8List>()).future);
}

void main() {
  final now = DateTime.now();

  group('earlierReportYears', () {
    test('offers the recorded years the two buttons do not already show', () {
      final at = DateTime(2026, 2, 14);
      expect(
        earlierReportYears([2026, 2025, 2023, 2021], at),
        [2023, 2021],
        reason: 'this year and last year are buttons, not menu entries',
      );
    });

    test('offers nothing when every recorded year is already a button', () {
      expect(earlierReportYears([2026, 2025], DateTime(2026, 2, 14)), isEmpty);
      expect(earlierReportYears([], DateTime(2026, 2, 14)), isEmpty);
    });

    test('does not invent years the org has no intakes for', () {
      // A gap between 2019 and 2024 stays a gap: there is nothing in 2020–2023
      // to report, and offering it would only produce an empty document.
      expect(
        earlierReportYears([2024, 2019], DateTime(2026, 2, 14)),
        [2024, 2019],
      );
    });
  });

  testWidgets('defaults to the year in progress', (tester) async {
    final repo = MockCaseReportRepo();
    _stubPending(repo);

    await _pump(tester, repo);
    expect(find.text('${now.year}'), findsOneWidget);
    expect(find.text('${now.year - 1}'), findsOneWidget);

    await tester.tap(find.text('PDF report'));
    await tester.pump();

    // `csv` is left at its default: mocktail records the default, so naming it
    // would only trip avoid_redundant_argument_values. The CSV button's own
    // call is verified with csv: true below.
    verify(
      () => repo.fetchAnnualReport(
        year: now.year,
        lang: 'en',
        tzOffsetMinutes: now.timeZoneOffset.inMinutes,
      ),
    ).called(1);
  });

  testWidgets('last year is one tap away', (tester) async {
    final repo = MockCaseReportRepo();
    _stubPending(repo);

    await _pump(tester, repo);
    await tester.tap(find.text('${now.year - 1}'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PDF report'));
    await tester.pump();

    verify(
      () => repo.fetchAnnualReport(
        year: now.year - 1,
        lang: 'en',
        tzOffsetMinutes: now.timeZoneOffset.inMinutes,
      ),
    ).called(1);
  });

  testWidgets('an earlier year is picked from the menu and becomes a button', (
    tester,
  ) async {
    final repo = MockCaseReportRepo();
    _stubPending(repo);

    await _pump(tester, repo, intakeYears: [now.year, now.year - 1, 2019]);
    // Not a button until it has been chosen — the control stays compact.
    expect(find.text('2019'), findsNothing);

    await tester.tap(find.text('Earlier years'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2019').last);
    await tester.pumpAndSettle();

    // Picking it both selects the period and adds the button, so there is no
    // second step and no competing control showing a different year.
    expect(find.text('2019'), findsOneWidget);
    await tester.tap(find.text('PDF report'));
    await tester.pump();

    verify(
      () => repo.fetchAnnualReport(
        year: 2019,
        lang: 'en',
        tzOffsetMinutes: now.timeZoneOffset.inMinutes,
      ),
    ).called(1);
  });

  testWidgets('the picker is absent when there is no earlier year on record', (
    tester,
  ) async {
    final repo = MockCaseReportRepo();
    _stubPending(repo);

    await _pump(tester, repo, intakeYears: [now.year]);

    expect(find.text('Earlier years'), findsNothing);
    // The two recent years and "all time" are always offered regardless.
    expect(find.text('All time'), findsOneWidget);
  });

  testWidgets('four period buttons still fit a narrow phone', (tester) async {
    // A picked year adds a fourth segment, which is the widest this control
    // ever gets ("2026 | 2025 | 2019 | All time"). Overflow in a test surfaces
    // as a thrown layout exception, so this passing IS the assertion — at the
    // narrowest width the app supports.
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repo = MockCaseReportRepo();
    _stubPending(repo);

    await _pump(tester, repo, intakeYears: [now.year, now.year - 1, 2019]);
    await tester.tap(find.text('Earlier years'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2019').last);
    await tester.pumpAndSettle();

    expect(find.byType(SegmentedButton<int?>), findsOneWidget);
    expect(find.text('2019'), findsOneWidget);
    expect(find.text('All time'), findsOneWidget);
  });

  testWidgets('the CSV button asks for the same report in the other format', (
    tester,
  ) async {
    final repo = MockCaseReportRepo();
    _stubPending(repo);

    await _pump(tester, repo);
    // "All time" drops the year entirely rather than sending one.
    await tester.tap(find.text('All time'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CSV table'));
    await tester.pump();

    // `year` is deliberately absent, not passed as null — the parameter's
    // default IS null, and case_report_repository_test asserts that a null
    // year omits the query param altogether.
    verify(
      () => repo.fetchAnnualReport(
        csv: true,
        lang: 'en',
        tzOffsetMinutes: now.timeZoneOffset.inMinutes,
      ),
    ).called(1);
  });

  testWidgets(
    'only the tapped format shows a spinner, and nothing else is tappable',
    (tester) async {
      final repo = MockCaseReportRepo();
      _stubPending(repo, Completer<Uint8List>());

      await _pump(tester, repo, intakeYears: [now.year, 2019]);
      await tester.tap(find.text('CSV table'));
      await tester.pump();

      // The CSV button's icon became the spinner; the PDF button keeps its
      // label (it is disabled, not busy) — a second tap must not launch a
      // second load and a second share sheet.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('PDF report'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull,
      );
      // The period cannot be changed mid-export either, by segment or by
      // picker — the request already named a year.
      expect(
        tester
            .widget<SegmentedButton<int?>>(find.byType(SegmentedButton<int?>))
            .onSelectionChanged,
        isNull,
      );
      expect(
        tester
            .widget<PopupMenuButton<int>>(find.byType(PopupMenuButton<int>))
            .enabled,
        isFalse,
      );
    },
  );

  testWidgets('a failed export reports it and restores the buttons', (
    tester,
  ) async {
    final repo = MockCaseReportRepo();
    when(
      () => repo.fetchAnnualReport(
        year: any(named: 'year'),
        csv: any(named: 'csv'),
        lang: any(named: 'lang'),
        tzOffsetMinutes: any(named: 'tzOffsetMinutes'),
      ),
    ).thenThrow(
      const RepositoryException('nope', kind: RepositoryErrorKind.network),
    );

    await _pump(tester, repo);
    await tester.tap(find.text('PDF report'));
    await tester.pumpAndSettle();

    expect(find.textContaining("You're offline"), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });
}
