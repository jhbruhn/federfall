import 'package:federfall/features/worklist/today_screen.dart';
import 'package:federfall/features/worklist/worklist.dart';
import 'package:federfall/features/worklist/worklist_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 6, 24, 12);

Future<void> _pump(WidgetTester tester, List<WorklistItem> items) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [worklistProvider.overrideWith((ref) async => items)],
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: TodayScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the empty state when nothing is due', (tester) async {
    await _pump(tester, const []);
    expect(find.text("Nothing due — you're all caught up."), findsOneWidget);
  });

  testWidgets('groups items by kind with case numbers', (tester) async {
    await _pump(tester, [
      WorklistItem(
        kind: WorklistKind.medicationDue,
        caseId: 'c1',
        caseNumber: '2026-001',
        animalName: 'Flora',
        dueAt: _now.subtract(const Duration(hours: 1)),
        severity: WorklistSeverity.overdue,
        drug: 'Meloxicam',
      ),
      WorklistItem(
        kind: WorklistKind.staleCase,
        caseId: 'c2',
        caseNumber: '2026-002',
        dueAt: _now.subtract(const Duration(days: 9)),
        severity: WorklistSeverity.overdue,
      ),
    ]);

    expect(find.text('Medications due'), findsOneWidget);
    expect(find.text('Inactive cases'), findsOneWidget);
    // Title combines case number and animal name.
    expect(find.text('2026-001 · Flora'), findsOneWidget);
    expect(find.text('2026-002'), findsOneWidget);
    // Med detail combines drug + relative due; overdue shows by how long.
    expect(find.textContaining('Meloxicam'), findsOneWidget);
    expect(find.textContaining('Overdue by'), findsOneWidget);
  });

  testWidgets('a med due with a prescription offers a log-dose shortcut', (
    tester,
  ) async {
    await _pump(tester, [
      WorklistItem(
        kind: WorklistKind.medicationDue,
        caseId: 'c1',
        caseNumber: '2026-001',
        dueAt: _now.subtract(const Duration(hours: 2)),
        severity: WorklistSeverity.overdue,
        drug: 'Meloxicam',
        medication: const Medication(id: 'm1', caseId: 'c1', drug: 'Meloxicam'),
      ),
    ]);

    expect(find.byTooltip('Log dose'), findsOneWidget);
  });
}
