import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/medications/administration_sheet.dart';
import 'package:federfall/features/cases/medications/medication_products_providers.dart';
import 'package:federfall/features/cases/medications/medication_routes_providers.dart';
import 'package:federfall/features/cases/medications/medication_tiles.dart';
import 'package:federfall/features/cases/medications/prescription_sheet.dart';
import 'package:federfall/features/cases/weights/weights_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockMedicationsRepo extends Mock implements PbMedicationsRepository {}

class MockAdministrationsRepo extends Mock
    implements PbMedicationAdministrationsRepository {}

void main() {
  setUpAll(() => registerFallbackValue(<String, dynamic>{}));

  late MockMedicationsRepo medications;
  late MockAdministrationsRepo administrations;

  setUp(() {
    medications = MockMedicationsRepo();
    administrations = MockAdministrationsRepo();
  });

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    List<Weight> weights = const [],
    List<MedicationProduct> catalogue = const [],
  }) async {
    final container = ProviderContainer(
      overrides: [
        weightsForCaseProvider('c1').overrideWith((ref) async => weights),
        activeMedicationProductsProvider.overrideWith((ref) async => catalogue),
        currentUserProvider.overrideWith(
          (ref) async =>
              const AppUser(id: 'u1', email: 'me@x.org', org: 'org1'),
        ),
        medicationsRepositoryProvider.overrideWith((ref) async => medications),
        medicationAdministrationsRepositoryProvider.overrideWith(
          (ref) async => administrations,
        ),
        medicationRoutesProvider.overrideWith(
          (ref) async => const [
            MedicationRoute(id: 'mr_subcut', label: 'Subcutaneous'),
          ],
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: child),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    final submit = find.widgetWithText(FilledButton, 'Save');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
  }

  group('PrescriptionSheet', () {
    testWidgets('creates a prescription with a controlled flag', (
      tester,
    ) async {
      when(() => medications.create(any())).thenAnswer(
        (_) async => const Medication(id: 'm1', caseId: 'c1', drug: 'x'),
      );

      await pump(tester, const PrescriptionSheet(caseId: 'c1'));
      await tester.enterText(find.byType(TextField).first, 'Baytril');
      await tester.ensureVisible(find.text('Controlled drug'));
      await tester.tap(find.text('Controlled drug'));
      await tester.pumpAndSettle();
      await save(tester);

      final body =
          verify(() => medications.create(captureAny())).captured.single
              as Map<String, dynamic>;
      expect(body['drug'], 'Baytril');
      expect(body['is_controlled'], true);
      expect(body['case'], 'c1');
      expect(body['org'], 'org1');
      // Default frequency preset is once-daily → structured q24h.
      expect(body['frequency_kind'], 'scheduled');
      expect(body['interval_hours'], 24);
    });

    testWidgets('stores a per-kilogram rate and the product strength', (
      tester,
    ) async {
      when(() => medications.create(any())).thenAnswer(
        (_) async => const Medication(id: 'm1', caseId: 'c1', drug: 'x'),
      );

      await pump(
        tester,
        const PrescriptionSheet(caseId: 'c1'),
        weights: [
          Weight(
            id: 'w1',
            animal: 'a1',
            weightG: 262,
            measuredAt: DateTime.now(),
          ),
        ],
      );
      await tester.enterText(find.byType(TextField).first, 'Baytril');
      await tester.enterText(
        find.widgetWithText(TextField, 'Unit'),
        'mg',
      );
      // One dose number, read per kilogram once the switch is on.
      await tester.ensureVisible(find.text('Dose per kg body weight'));
      await tester.tap(find.text('Dose per kg body weight'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Dose'), '20');
      await tester.enterText(
        find.widgetWithText(TextField, 'Product concentration'),
        '15',
      );
      await tester.pumpAndSettle();

      // The plan shows what its rate means for this bird right now, so a typo
      // is obvious while writing it rather than at the syringe.
      expect(find.text('0.3493 ml'), findsOneWidget);
      expect(find.text('20 mg/kg × 262 g = 5.24 mg'), findsOneWidget);

      await save(tester);

      final body =
          verify(() => medications.create(captureAny())).captured.single
              as Map<String, dynamic>;
      expect(body['dose_rate'], 20);
      // The flat-dose column is cleared, so the plan carries one dosing rule.
      expect(body['dose'], isNull);
      expect(body['concentration_per_ml'], 15);
      expect(body['dose_unit'], 'mg');
    });

    testWidgets('a catalogue entry fills the form and flags a wild rate', (
      tester,
    ) async {
      when(() => medications.create(any())).thenAnswer(
        (_) async => const Medication(id: 'm1', caseId: 'c1', drug: 'x'),
      );

      await pump(
        tester,
        const PrescriptionSheet(caseId: 'c1'),
        weights: [
          Weight(
            id: 'w1',
            animal: 'a1',
            weightG: 262,
            measuredAt: DateTime.now(),
          ),
        ],
        catalogue: const [
          MedicationProduct(
            id: 'p1',
            label: 'Medikament 1',
            doseUnit: 'mg',
            doseRate: 20,
            rateMin: 10,
            rateMax: 30,
            concentrationPerMl: 15,
          ),
        ],
      );

      await tester.tap(find.text('From the drug catalogue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Medikament 1').last);
      await tester.pumpAndSettle();

      // The entry poured itself into the form: drug, unit, rate (per kg) and
      // strength, which is enough to show the dose for this bird.
      expect(find.text('0.3493 ml'), findsOneWidget);
      expect(find.text('20 mg/kg × 262 g = 5.24 mg'), findsOneWidget);

      // Ten times the catalogue's upper bound: warned, but still savable —
      // the vet in front of the bird outranks the list.
      await tester.enterText(find.widgetWithText(TextField, 'Dose'), '300');
      await tester.pumpAndSettle();
      expect(
        find.text('Outside the recorded range for Medikament 1 (10–30 mg/kg).'),
        findsOneWidget,
      );

      await save(tester);
      final body =
          verify(() => medications.create(captureAny())).captured.single
              as Map<String, dynamic>;
      expect(body['drug'], 'Medikament 1');
      expect(body['dose_rate'], 300);
      expect(body['concentration_per_ml'], 15);
    });

    testWidgets('a chosen preset stores its interval', (tester) async {
      when(() => medications.create(any())).thenAnswer(
        (_) async => const Medication(id: 'm1', caseId: 'c1', drug: 'x'),
      );

      await pump(tester, const PrescriptionSheet(caseId: 'c1'));
      await tester.enterText(find.byType(TextField).first, 'Baytril');
      // Open the frequency dropdown (showing the default) and pick twice-daily.
      await tester.ensureVisible(find.text('Once daily'));
      await tester.tap(find.text('Once daily'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Twice daily').last);
      await tester.pumpAndSettle();
      await save(tester);

      final body =
          verify(() => medications.create(captureAny())).captured.single
              as Map<String, dynamic>;
      expect(body['frequency_kind'], 'scheduled');
      expect(body['interval_hours'], 12);
    });
  });

  group('AdministrationSheet', () {
    testWidgets('logging a dose from a plan links and prefills it', (
      tester,
    ) async {
      when(() => administrations.create(any())).thenAnswer(
        (_) async =>
            const MedicationAdministration(id: 'a1', caseId: 'c1', drug: 'x'),
      );

      const plan = Medication(
        id: 'm1',
        caseId: 'c1',
        drug: 'Baytril',
        dose: 0.3,
        doseUnit: 'ml',
        route: 'mr_subcut',
      );
      await pump(
        tester,
        const AdministrationSheet(caseId: 'c1', plan: plan),
      );

      // Drug is prefilled from the plan.
      expect(find.text('Baytril'), findsOneWidget);
      await save(tester);

      final body =
          verify(() => administrations.create(captureAny())).captured.single
              as Map<String, dynamic>;
      expect(body['drug'], 'Baytril');
      expect(body['medication'], 'm1');
      expect(body['administered_by'], 'u1');
      expect(body['route'], 'mr_subcut');
    });
  });

  group('medication tiles', () {
    testWidgets('prescription tile shows drug, regimen and controlled badge', (
      tester,
    ) async {
      await pump(
        tester,
        const PrescriptionTile(
          plan: Medication(
            id: 'm1',
            caseId: 'c1',
            drug: 'Baytril',
            dose: 0.3,
            doseUnit: 'ml',
            route: 'mr_subcut',
            frequencyKind: MedicationFrequencyKind.scheduled,
            intervalHours: 12,
            isControlled: true,
          ),
          caseId: 'c1',
        ),
      );

      expect(find.text('Prescribed Baytril'), findsOneWidget);
      expect(find.text('0.3 ml · Subcutaneous · Twice daily'), findsOneWidget);
      expect(find.text('Controlled'), findsOneWidget);
    });

    testWidgets('inline log-dose button shows only on an active plan', (
      tester,
    ) async {
      // No end date → still being given → inline action present.
      await pump(
        tester,
        const PrescriptionTile(
          plan: Medication(id: 'm1', caseId: 'c1', drug: 'Baytril'),
          caseId: 'c1',
        ),
      );
      expect(find.widgetWithText(FilledButton, 'Log dose'), findsOneWidget);

      // Ended in the past → no inline action.
      await pump(
        tester,
        PrescriptionTile(
          plan: Medication(
            id: 'm1',
            caseId: 'c1',
            drug: 'Baytril',
            endedAt: DateTime.utc(2020),
          ),
          caseId: 'c1',
        ),
      );
      expect(find.widgetWithText(FilledButton, 'Log dose'), findsNothing);
    });

    testWidgets('administration tile shows the dose and deletes', (
      tester,
    ) async {
      when(() => administrations.delete('a1')).thenAnswer((_) async {});

      await pump(
        tester,
        const AdministrationTile(
          administration: MedicationAdministration(
            id: 'a1',
            caseId: 'c1',
            drug: 'Baytril',
            dose: 0.3,
            doseUnit: 'ml',
          ),
          caseId: 'c1',
        ),
      );

      expect(find.text('Gave Baytril 0.3 ml'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();

      verify(() => administrations.delete('a1')).called(1);
    });
  });
}
