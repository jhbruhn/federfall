import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/worklist/worklist.dart';
import 'package:federfall/features/worklist/worklist_tile.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart' hide Finder;
import 'package:flutter_test/flutter_test.dart' as ft show Finder;
import 'package:mocktail/mocktail.dart';

class _MockAdministrations extends Mock
    implements PbMedicationAdministrationsRepository {}

class _MockWeights extends Mock implements PbWeightsRepository {}

final _now = DateTime(2026, 6, 24, 12);

/// A dose logged straight from a worklist row (federfall-78k6.3). The guard
/// under test is the one that decides whether one tap may write a number at
/// all: a flat prescription determines it, a per-kilogram rate only does so
/// against a weight worth trusting.
void main() {
  late _MockAdministrations administrations;
  late _MockWeights weights;

  setUpAll(() => registerFallbackValue(<String, dynamic>{}));

  setUp(() {
    administrations = _MockAdministrations();
    weights = _MockWeights();
    when(() => administrations.create(any())).thenAnswer(
      (_) async => const MedicationAdministration(id: 'a1', caseId: 'c1', drug: 'x'),
    );
    when(() => administrations.delete(any())).thenAnswer((_) async {});
    when(() => weights.forCase(any())).thenAnswer((_) async => const []);
  });

  WorklistItem due(Medication plan) => WorklistItem(
    kind: WorklistKind.medicationDue,
    caseId: 'c1',
    caseNumber: '2026-001',
    dueAt: _now.subtract(const Duration(hours: 1)),
    severity: WorklistSeverity.overdue,
    drug: plan.drug,
    medication: plan,
  );

  Future<void> pump(WidgetTester tester, WorklistItem item) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          medicationAdministrationsRepositoryProvider.overrideWith(
            (ref) async => administrations,
          ),
          weightsRepositoryProvider.overrideWith((ref) async => weights),
          currentUserProvider.overrideWith(
            (ref) async =>
                const AppUser(id: 'u1', email: 'a@x.org', org: 'org1'),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ListView(children: [WorklistTile(item: item, now: _now)]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  ft.Finder logDose() => find.byTooltip('Log dose');

  testWidgets('a flat prescription is written in one tap, from the plan', (
    tester,
  ) async {
    await pump(
      tester,
      due(
        const Medication(
          id: 'm1',
          caseId: 'c1',
          drug: 'Meloxicam',
          dose: 0.5,
          doseUnit: 'mg',
          route: 'po',
        ),
      ),
    );

    await tester.tap(logDose());
    await tester.pumpAndSettle();

    final body =
        verify(() => administrations.create(captureAny())).captured.single
            as Map<String, dynamic>;
    expect(body['medication'], 'm1');
    expect(body['drug'], 'Meloxicam');
    expect(body['dose'], 0.5);
    expect(body['dose_unit'], 'mg');
    expect(body['route'], 'po');
    expect(body['administered_by'], 'u1');
    expect(body['org'], 'org1');
    // Nothing was derived, so nothing claims a weight produced it.
    expect(body['weight_g_used'], isNull);
  });

  testWidgets('the confirmation takes the dose back', (tester) async {
    await pump(
      tester,
      due(const Medication(id: 'm1', caseId: 'c1', drug: 'Meloxicam', dose: 1)),
    );

    await tester.tap(logDose());
    await tester.pumpAndSettle();
    expect(find.text('Dose logged'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    verify(() => administrations.delete('a1')).called(1);
  });

  testWidgets('a per-kilogram rate resolves against a current weight', (
    tester,
  ) async {
    when(() => weights.forCase('c1')).thenAnswer(
      (_) async => [
        Weight(
          id: 'w1',
          animal: 'a1',
          caseId: 'c1',
          weightG: 400,
          measuredAt: DateTime.now(),
        ),
      ],
    );

    await pump(
      tester,
      due(
        const Medication(
          id: 'm1',
          caseId: 'c1',
          drug: 'Enrofloxacin',
          doseRate: 10,
          doseUnit: 'mg',
        ),
      ),
    );

    await tester.tap(logDose());
    await tester.pumpAndSettle();

    final body =
        verify(() => administrations.create(captureAny())).captured.single
            as Map<String, dynamic>;
    // 10 mg/kg on 400 g.
    expect(body['dose'], 4.0);
    expect(body['weight_g_used'], 400.0);
  });

  testWidgets('a per-kilogram rate with no weight on record writes nothing', (
    tester,
  ) async {
    await pump(
      tester,
      due(
        const Medication(
          id: 'm1',
          caseId: 'c1',
          drug: 'Enrofloxacin',
          doseRate: 10,
          doseUnit: 'mg',
        ),
      ),
    );

    await tester.tap(logDose());
    await tester.pumpAndSettle();

    // One tap must never invent a number: the sheet takes over instead.
    verifyNever(() => administrations.create(any()));
  });

  testWidgets('a weight nobody has checked in days is not enough either', (
    tester,
  ) async {
    when(() => weights.forCase('c1')).thenAnswer(
      (_) async => [
        Weight(
          id: 'w1',
          animal: 'a1',
          caseId: 'c1',
          weightG: 400,
          measuredAt: DateTime.now().subtract(const Duration(days: 5)),
        ),
      ],
    );

    await pump(
      tester,
      due(
        const Medication(
          id: 'm1',
          caseId: 'c1',
          drug: 'Enrofloxacin',
          doseRate: 10,
          doseUnit: 'mg',
        ),
      ),
    );

    await tester.tap(logDose());
    await tester.pumpAndSettle();

    verifyNever(() => administrations.create(any()));
  });
}
