import 'dart:async';
import 'dart:typed_data';

import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/statistics/annual_report_sheet.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockCaseReportRepo extends Mock implements PbCaseReportRepository {}

/// Pumps the sheet against [repo]. The sheet is pumped directly rather than
/// through `showAnnualReportSheet` — a modal route would only add a frame of
/// animation to every expectation here.
Future<void> _pump(WidgetTester tester, PbCaseReportRepository repo) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        caseReportRepositoryProvider.overrideWith((ref) async => repo),
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

void main() {
  final now = DateTime.now();

  group('ReportPeriod', () {
    test('resolves each option to the year the report route wants', () {
      final at = DateTime(2026, 2, 14);
      expect(ReportPeriod.lastYear.yearAt(at), 2025);
      expect(ReportPeriod.thisYear.yearAt(at), 2026);
      // Null is "no ?year=", i.e. every case on record — not "the current
      // year", which is what a 0 or a -1 sentinel would have risked.
      expect(ReportPeriod.allTime.yearAt(at), isNull);
    });
  });

  testWidgets('defaults to the year just ended — the one that gets filed', (
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
      // Never completes: this asserts what was REQUESTED, and completing it
      // would hand bytes to the platform share channel, which a widget test
      // has no implementation for.
    ).thenAnswer((_) => Completer<Uint8List>().future);

    await _pump(tester, repo);
    expect(find.text('${now.year - 1}'), findsOneWidget);

    await tester.tap(find.text('PDF report'));
    await tester.pump();

    // `csv` is left at its default here for the same reason `year` is in the
    // next test: mocktail records the default, so naming it would only trip
    // avoid_redundant_argument_values. The CSV button's own call is verified
    // with csv: true below, which is what makes this one meaningful.
    verify(
      () => repo.fetchAnnualReport(
        year: now.year - 1,
        lang: 'en',
        tzOffsetMinutes: now.timeZoneOffset.inMinutes,
      ),
    ).called(1);
  });

  testWidgets('the CSV button asks for the same report in the other format', (
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
    ).thenAnswer((_) => Completer<Uint8List>().future);

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
    'only the tapped format shows a spinner, and neither is tappable',
    (
      tester,
    ) async {
      final repo = MockCaseReportRepo();
      final pending = Completer<Uint8List>();
      when(
        () => repo.fetchAnnualReport(
          year: any(named: 'year'),
          csv: any(named: 'csv'),
          lang: any(named: 'lang'),
          tzOffsetMinutes: any(named: 'tzOffsetMinutes'),
        ),
      ).thenAnswer((_) => pending.future);

      await _pump(tester, repo);
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
      // The period cannot be changed mid-export either — the request already
      // named a year.
      expect(
        tester
            .widget<SegmentedButton<ReportPeriod>>(
              find.byType(SegmentedButton<ReportPeriod>),
            )
            .onSelectionChanged,
        isNull,
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
      const RepositoryException(
        'nope',
        kind: RepositoryErrorKind.network,
      ),
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
