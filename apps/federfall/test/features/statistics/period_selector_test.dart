import 'package:federfall/features/statistics/period_selector.dart';
import 'package:federfall/features/statistics/statistics_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<StatsPeriod?> _pumpAndPick(
  WidgetTester tester,
  StatsPeriod selected,
  Future<void> Function(WidgetTester tester) act, {
  List<int> intakeYears = const [],
}) async {
  StatsPeriod? picked;
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: PeriodSelector(
          selected: selected,
          intakeYears: intakeYears,
          now: DateTime(2026, 2, 14),
          onChanged: (p) => picked = p,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await act(tester);
  await tester.pumpAndSettle();
  return picked;
}

void main() {
  group('earlierReportYears', () {
    test('offers the recorded years the two buttons do not already show', () {
      expect(
        earlierReportYears([2026, 2025, 2023, 2021], DateTime(2026, 2, 14)),
        [2023, 2021],
      );
    });
  });

  testWidgets('a month narrows the selected year', (tester) async {
    final picked = await _pumpAndPick(
      tester,
      const StatsPeriod(year: 2026),
      (tester) async {
        await tester.tap(find.text('Whole year'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('March').last);
      },
    );

    expect(picked?.year, 2026);
    expect(picked?.month, 3);
  });

  testWidgets('all time offers no month at all', (tester) async {
    // A month without a year names no period — the server refuses it, and the
    // control does not offer it either.
    await _pumpAndPick(tester, StatsPeriod.allTime, (_) async {});

    expect(find.text('Whole year'), findsNothing);
  });

  testWidgets('leaving a year for all time drops the month with it', (
    tester,
  ) async {
    final picked = await _pumpAndPick(
      tester,
      const StatsPeriod(year: 2026, month: 3),
      (tester) async => tester.tap(find.text('All time')),
    );

    expect(picked?.isAllTime, isTrue);
    expect(picked?.month, isNull);
  });

  testWidgets('switching year keeps the month being compared', (tester) async {
    // Reading March 2026 and then tapping 2025 asks for March 2025, not for
    // the whole of 2025 — the question was about a month.
    final picked = await _pumpAndPick(
      tester,
      const StatsPeriod(year: 2026, month: 3),
      (tester) async => tester.tap(find.text('2025')),
    );

    expect(picked?.year, 2025);
    expect(picked?.month, 3);
  });
}
