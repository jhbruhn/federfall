import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/medications/administration_sheet.dart';
import 'package:federfall/features/cases/medications/medication_tiles.dart';
import 'package:federfall/features/cases/medications/prescription_sheet.dart';
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

  Future<void> pump(WidgetTester tester, Widget child) async {
    final container = ProviderContainer(
      overrides: [
        currentUserProvider.overrideWith(
          (ref) async =>
              const AppUser(id: 'u1', email: 'me@x.org', org: 'org1'),
        ),
        medicationsRepositoryProvider
            .overrideWith((ref) async => medications),
        medicationAdministrationsRepositoryProvider
            .overrideWith((ref) async => administrations),
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
    testWidgets('creates a prescription with a controlled flag',
        (tester) async {
      when(() => medications.create(any())).thenAnswer(
        (_) async => const Medication(id: 'm1', caseId: 'c1', drug: 'x'),
      );

      await pump(tester, const PrescriptionSheet(caseId: 'c1'));
      await tester.enterText(find.byType(TextField).first, 'Baytril');
      await tester.tap(find.text('Controlled drug'));
      await tester.pumpAndSettle();
      await save(tester);

      final body = verify(() => medications.create(captureAny()))
          .captured
          .single as Map<String, dynamic>;
      expect(body['drug'], 'Baytril');
      expect(body['is_controlled'], true);
      expect(body['case'], 'c1');
      expect(body['org'], 'org1');
      // Default frequency preset is once-daily → structured q24h.
      expect(body['frequency_kind'], 'scheduled');
      expect(body['interval_hours'], 24);
    });

    testWidgets('a chosen preset stores its interval', (tester) async {
      when(() => medications.create(any())).thenAnswer(
        (_) async => const Medication(id: 'm1', caseId: 'c1', drug: 'x'),
      );

      await pump(tester, const PrescriptionSheet(caseId: 'c1'));
      await tester.enterText(find.byType(TextField).first, 'Baytril');
      // Open the frequency dropdown (showing the default) and pick twice-daily.
      await tester.tap(find.text('Once daily'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Twice daily').last);
      await tester.pumpAndSettle();
      await save(tester);

      final body = verify(() => medications.create(captureAny()))
          .captured
          .single as Map<String, dynamic>;
      expect(body['frequency_kind'], 'scheduled');
      expect(body['interval_hours'], 12);
    });
  });

  group('AdministrationSheet', () {
    testWidgets('logging a dose from a plan links and prefills it',
        (tester) async {
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
        route: MedicationRoute.subcutaneous,
      );
      await pump(
        tester,
        const AdministrationSheet(caseId: 'c1', plan: plan),
      );

      // Drug is prefilled from the plan.
      expect(find.text('Baytril'), findsOneWidget);
      await save(tester);

      final body = verify(() => administrations.create(captureAny()))
          .captured
          .single as Map<String, dynamic>;
      expect(body['drug'], 'Baytril');
      expect(body['medication'], 'm1');
      expect(body['administered_by'], 'u1');
      expect(body['route'], 'subcutaneous');
    });
  });

  group('medication tiles', () {
    testWidgets('prescription tile shows drug, regimen and controlled badge',
        (tester) async {
      await pump(
        tester,
        const PrescriptionTile(
          plan: Medication(
            id: 'm1',
            caseId: 'c1',
            drug: 'Baytril',
            dose: 0.3,
            doseUnit: 'ml',
            route: MedicationRoute.subcutaneous,
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

    testWidgets('inline log-dose button shows only on an active plan',
        (tester) async {
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

    testWidgets('administration tile shows the dose and deletes',
        (tester) async {
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
