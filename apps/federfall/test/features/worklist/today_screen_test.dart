import 'package:federfall/features/worklist/today_screen.dart';
import 'package:federfall/features/worklist/worklist.dart';
import 'package:federfall/features/worklist/worklist_dismissals.dart';
import 'package:federfall/features/worklist/worklist_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 6, 24, 12);

/// Stands in for the real store so a screen test never reaches
/// SharedPreferences — the store's own expiry rules are covered in
/// `worklist_dismissals_test.dart`, and mocking the prefs channel here would
/// let the unrelated server/connection providers start resolving.
class _FakeDismissals extends WorklistDismissals {
  final dismissed = <String>{};

  @override
  Future<Set<String>> build() async => dismissed;

  @override
  Future<void> dismiss(String key) async {
    dismissed.add(key);
    state = AsyncData({...dismissed});
  }

  @override
  Future<void> restore(String key) async {
    dismissed.remove(key);
    state = AsyncData({...dismissed});
  }
}

Future<_FakeDismissals> _pump(
  WidgetTester tester,
  List<WorklistItem> items,
) async {
  final dismissals = _FakeDismissals();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        worklistProvider.overrideWith((ref) async => items),
        worklistDismissalsProvider.overrideWith(() => dismissals),
      ],
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: TodayScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return dismissals;
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
        kind: WorklistKind.quarantineEnding,
        caseId: 'c2',
        caseNumber: '2026-002',
        dueAt: _now,
        severity: WorklistSeverity.upcoming,
      ),
    ]);

    expect(find.text('Medications due'), findsOneWidget);
    expect(find.text('Quarantine ending'), findsOneWidget);
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

  testWidgets('a vet appointment names the practice and can be marked kept '
      'from the row, with cancelling behind the overflow (federfall-78k6.3)', (
    tester,
  ) async {
    await _pump(tester, [
      WorklistItem(
        kind: WorklistKind.vetAppointment,
        caseId: 'c1',
        caseNumber: '2026-004',
        animalName: 'Otto',
        dueAt: _now.add(const Duration(hours: 3)),
        severity: WorklistSeverity.upcoming,
        appointment: VetAppointment(
          id: 'v1',
          caseId: 'c1',
          startsAt: _now.add(const Duration(hours: 3)),
          vet: 'Dr. Meyer',
        ),
      ),
    ]);

    expect(find.text('Vet appointments'), findsOneWidget);
    expect(find.text('2026-004 · Otto'), findsOneWidget);
    expect(find.textContaining('Dr. Meyer'), findsOneWidget);
    expect(find.byTooltip('Mark as attended'), findsOneWidget);

    // The visit that did NOT happen is one level down, so the row's own tap
    // target stays the common answer.
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    expect(find.text('Cancel appointment'), findsOneWidget);
  });

  testWidgets('no row falls back to a chevron (federfall-78k6.3)', (
    tester,
  ) async {
    // The chevron only ever meant "this kind has no verb". Every kind has one
    // now, so its presence anywhere is the regression.
    await _pump(tester, [
      WorklistItem(
        kind: WorklistKind.medicationDue,
        caseId: 'c1',
        dueAt: _now,
        severity: WorklistSeverity.upcoming,
        drug: 'Meloxicam',
        medication: const Medication(id: 'm1', caseId: 'c1', drug: 'Meloxicam'),
      ),
      WorklistItem(
        kind: WorklistKind.followUpDue,
        caseId: 'c2',
        dueAt: _now,
        severity: WorklistSeverity.upcoming,
        followUp: FollowUp(id: 'f1', caseId: 'c2', dueAt: _now),
      ),
      WorklistItem(
        kind: WorklistKind.vetAppointment,
        caseId: 'c3',
        dueAt: _now,
        severity: WorklistSeverity.upcoming,
        appointment: VetAppointment(id: 'v1', caseId: 'c3', startsAt: _now),
      ),
      WorklistItem(
        kind: WorklistKind.quarantineEnding,
        caseId: 'c4',
        dueAt: _now,
        severity: WorklistSeverity.upcoming,
      ),
    ]);

    expect(find.byIcon(Icons.chevron_right), findsNothing);
  });

  testWidgets('a quarantine ending is acknowledged, not "ended" — the row '
      'goes quiet for the day (federfall-78k6.3)', (tester) async {
    final item = WorklistItem(
      kind: WorklistKind.quarantineEnding,
      caseId: 'c1',
      caseNumber: '2026-002',
      dueAt: _now,
      severity: WorklistSeverity.upcoming,
    );
    final dismissals = await _pump(tester, [item]);

    await tester.tap(find.byTooltip('Got it'));
    await tester.pumpAndSettle();

    expect(dismissals.dismissed, {worklistDismissalKey(item)});
    expect(find.text('Hidden until tomorrow'), findsOneWidget);
  });

  testWidgets('swiping a row dismisses it, and the snackbar takes it back', (
    tester,
  ) async {
    final item = WorklistItem(
      kind: WorklistKind.followUpDue,
      caseId: 'c1',
      caseNumber: '2026-003',
      dueAt: _now,
      severity: WorklistSeverity.upcoming,
      followUp: FollowUp(id: 'f1', caseId: 'c1', dueAt: _now),
    );
    final dismissals = await _pump(tester, [item]);

    await tester.drag(find.text('2026-003'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(dismissals.dismissed, {worklistDismissalKey(item)});

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(dismissals.dismissed, isEmpty);
  });

  testWidgets('wide screens show the worklist beside a selection placeholder', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pump(tester, [
      WorklistItem(
        kind: WorklistKind.quarantineEnding,
        caseId: 'c1',
        caseNumber: '2026-001',
        dueAt: _now,
        severity: WorklistSeverity.upcoming,
      ),
    ]);

    // Worklist on the left and, since nothing is selected yet, the empty
    // detail-pane placeholder on the right — both visible at once.
    expect(find.text('2026-001'), findsOneWidget);
    expect(find.text('Select a case to view its details'), findsOneWidget);
  });
}
