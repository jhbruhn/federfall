import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/medications/administration_sheet.dart';
import 'package:federfall/features/cases/medications/dose_calculator_panel.dart';
import 'package:federfall/features/cases/medications/medication_routes_providers.dart';
import 'package:federfall/features/cases/weights/weights_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/theme/app_theme.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart' hide Finder;
import 'package:mocktail/mocktail.dart';

class MockAdministrationsRepo extends Mock
    implements PbMedicationAdministrationsRepository {}

void main() {
  setUpAll(() => registerFallbackValue(<String, dynamic>{}));

  Weight weight(double grams, {Duration age = Duration.zero}) => Weight(
    id: 'w1',
    animal: 'a1',
    weightG: grams,
    measuredAt: DateTime.now().subtract(age),
  );

  /// The sheet's unit field, which the panel reads instead of owning one.
  late TextEditingController unitField;

  setUp(() => unitField = TextEditingController(text: 'mg'));
  tearDown(() => unitField.dispose());

  Future<void> pumpPanel(
    WidgetTester tester, {
    required void Function(CalculatedDose) onApply,
    List<Weight> weights = const [],
    String locale = 'en',
    double width = 400,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          weightsForCaseProvider('c1').overrideWith((ref) async => weights),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          locale: Locale(locale),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SizedBox(
              width: width,
              child: DoseCalculatorPanel(
                caseId: 'c1',
                unit: unitField,
                onApply: onApply,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();
  }

  Future<void> enter(
    WidgetTester tester,
    String label,
    String value,
  ) async {
    await tester.enterText(find.widgetWithText(TextField, label), value);
    await tester.pumpAndSettle();
  }

  group('DoseCalculatorPanel', () {
    testWidgets('derives the dose from the newest weight on the case', (
      tester,
    ) async {
      double? applied;
      String? appliedUnit;
      await pumpPanel(
        tester,
        weights: [weight(262)],
        onApply: (d) {
          applied = d.amount;
          appliedUnit = d.unit;
        },
      );

      await enter(tester, 'Dose per kg body weight', '20');

      // Without a concentration the amount is the answer.
      expect(find.text('5.24 mg'), findsOneWidget);
      expect(find.text('20 mg/kg × 262 g'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Use as dose'));
      await tester.pumpAndSettle();

      expect(applied, 5.24);
      expect(appliedUnit, 'mg');
    });

    testWidgets('leads with the volume to draw once a concentration is set', (
      tester,
    ) async {
      await pumpPanel(tester, weights: [weight(262)], onApply: (_) {});

      await enter(tester, 'Dose per kg body weight', '20');
      await enter(tester, 'Product concentration', '15');

      final answer = tester.widget<Text>(find.text('0.3493 ml'));
      final workedOut = tester.widget<Text>(
        find.text('20 mg/kg × 262 g = 5.24 mg'),
      );
      expect(
        answer.style?.fontSize,
        greaterThan(workedOut.style?.fontSize ?? 0),
      );
    });

    testWidgets('accepts a comma as the decimal separator', (tester) async {
      double? applied;
      await pumpPanel(
        tester,
        weights: [weight(262)],
        onApply: (d) => applied = d.amount,
      );

      await enter(tester, 'Dose per kg body weight', '0,5');
      await tester.tap(find.widgetWithText(FilledButton, 'Use as dose'));
      await tester.pumpAndSettle();

      expect(applied, 0.131);
    });

    testWidgets('picks the newest weight, not the last in the list', (
      tester,
    ) async {
      double? applied;
      await pumpPanel(
        tester,
        weights: [
          weight(262),
          weight(300, age: const Duration(days: 5)),
        ],
        onApply: (d) => applied = d.amount,
      );

      await enter(tester, 'Dose per kg body weight', '10');
      await tester.tap(find.widgetWithText(FilledButton, 'Use as dose'));
      await tester.pumpAndSettle();

      expect(applied, 2.62);
    });

    testWidgets('refuses to calculate without a weight', (tester) async {
      await pumpPanel(tester, onApply: (_) {});

      await enter(tester, 'Dose per kg body weight', '20');

      expect(
        find.text('No weight on record — weigh the bird before calculating.'),
        findsOneWidget,
      );
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Use as dose'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('warns when the weight is out of date but still calculates', (
      tester,
    ) async {
      await pumpPanel(
        tester,
        weights: [weight(262, age: const Duration(days: 10))],
        onApply: (_) {},
      );

      await enter(tester, 'Dose per kg body weight', '20');

      expect(
        find.text(
          'The last weighing is more than 3 days old — '
          'weigh again before dosing.',
        ),
        findsOneWidget,
      );
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Use as dose'),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('fits the longer German labels on a narrow sheet', (
      tester,
    ) async {
      await pumpPanel(
        tester,
        weights: [weight(262)],
        onApply: (_) {},
        locale: 'de',
        width: 320,
      );

      await enter(tester, 'Dosis pro kg Körpergewicht', '20');
      await enter(tester, 'Konzentration des Präparats', '15');

      // German numbers read with a comma, matching the separator the keyboard
      // next to them produces.
      expect(find.text('0,3493 ml'), findsOneWidget);
      expect(find.text('20 mg/kg × 262 g = 5,24 mg'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('takes a comma-typed rate and gives a comma-formatted dose', (
      tester,
    ) async {
      double? applied;
      await pumpPanel(
        tester,
        weights: [weight(262)],
        onApply: (d) => applied = d.amount,
        locale: 'de',
      );

      await enter(tester, 'Dosis pro kg Körpergewicht', '0,5');

      expect(find.text('0,131 mg'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Übernehmen'));
      await tester.pumpAndSettle();
      expect(applied, 0.131);
    });

    testWidgets('scrolls itself into view when opened below the fold', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            weightsForCaseProvider(
              'c1',
            ).overrideWith((ref) async => [weight(262)]),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: [
                    const SizedBox(height: 420),
                    DoseCalculatorPanel(
                      caseId: 'c1',
                      unit: unitField,
                      onApply: (_) {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();

      final field = tester.getRect(
        find.widgetWithText(TextField, 'Dose per kg body weight'),
      );
      expect(field.bottom, lessThanOrEqualTo(500));
      expect(field.top, greaterThanOrEqualTo(0));
    });

    testWidgets('follows the unit typed into the sheet', (tester) async {
      await pumpPanel(tester, weights: [weight(262)], onApply: (_) {});

      await enter(tester, 'Dose per kg body weight', '20');
      expect(find.text('20 mg/kg × 262 g'), findsOneWidget);

      unitField.text = 'IU';
      await tester.pumpAndSettle();

      // No unit field of its own to keep in sync — it reads the sheet's.
      expect(find.text('20 IU/kg × 262 g'), findsOneWidget);
      expect(find.text('5.24 IU'), findsOneWidget);
    });

    testWidgets('suggests a dilution for an undrawable volume', (tester) async {
      await pumpPanel(tester, weights: [weight(262)], onApply: (_) {});

      await enter(tester, 'Dose per kg body weight', '1');
      await enter(tester, 'Product concentration', '100');

      expect(
        find.text('Too little to draw up — dilute 1:100 and draw 0.262 ml.'),
        findsOneWidget,
      );
    });
  });

  group('AdministrationSheet', () {
    /// Pumps the dose sheet for a case with one 262 g weight on record.
    Future<void> pumpSheet(
      WidgetTester tester,
      MockAdministrationsRepo administrations,
      Medication plan,
    ) async {
      final container = ProviderContainer(
        overrides: [
          currentUserProvider.overrideWith(
            (ref) async =>
                const AppUser(id: 'u1', email: 'me@x.org', org: 'org1'),
          ),
          medicationAdministrationsRepositoryProvider.overrideWith(
            (ref) async => administrations,
          ),
          medicationRoutesProvider.overrideWith((ref) async => const []),
          weightsForCaseProvider(
            'c1',
          ).overrideWith((ref) async => [weight(262)]),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light,
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: AdministrationSheet(caseId: 'c1', plan: plan),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('opening the calculator brings it into view in the sheet', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final administrations = MockAdministrationsRepo();
      final container = ProviderContainer(
        overrides: [
          currentUserProvider.overrideWith(
            (ref) async =>
                const AppUser(id: 'u1', email: 'me@x.org', org: 'org1'),
          ),
          medicationAdministrationsRepositoryProvider.overrideWith(
            (ref) async => administrations,
          ),
          medicationRoutesProvider.overrideWith((ref) async => const []),
          weightsForCaseProvider(
            'c1',
          ).overrideWith((ref) async => [weight(262)]),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light,
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () =>
                      showAdministrationSheet(context, caseId: 'c1'),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();

      final field = tester.getRect(
        find.widgetWithText(TextField, 'Dose per kg body weight'),
      );
      expect(field.bottom, lessThanOrEqualTo(640));
      expect(field.top, greaterThanOrEqualTo(0));
    });

    testWidgets('logs the calculated dose the carer accepted', (tester) async {
      final administrations = MockAdministrationsRepo();
      when(() => administrations.create(any())).thenAnswer(
        (_) async =>
            const MedicationAdministration(id: 'ad1', caseId: 'c1', drug: 'x'),
      );

      final container = ProviderContainer(
        overrides: [
          currentUserProvider.overrideWith(
            (ref) async =>
                const AppUser(id: 'u1', email: 'me@x.org', org: 'org1'),
          ),
          medicationAdministrationsRepositoryProvider.overrideWith(
            (ref) async => administrations,
          ),
          medicationRoutesProvider.overrideWith((ref) async => const []),
          weightsForCaseProvider(
            'c1',
          ).overrideWith((ref) async => [weight(262)]),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light,
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(
              body: AdministrationSheet(
                caseId: 'c1',
                plan: Medication(
                  id: 'm1',
                  caseId: 'c1',
                  drug: 'Baytril',
                  doseUnit: 'mg',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Dose calculator'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(DoseCalculatorPanel),
          matching: find.widgetWithText(TextField, 'Dose per kg body weight'),
        ),
        '20',
      );
      await tester.pumpAndSettle();

      final apply = find.widgetWithText(FilledButton, 'Use as dose');
      await tester.ensureVisible(apply);
      await tester.tap(apply);
      await tester.pumpAndSettle();

      final save = find.widgetWithText(FilledButton, 'Save');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();

      final body =
          verify(() => administrations.create(captureAny())).captured.single
              as Map<String, dynamic>;
      expect(body['dose'], 5.24);
      expect(body['dose_unit'], 'mg');
      expect(body['medication'], 'm1');
      // The derivation rides along, so the record says why 5.24 mg.
      expect(body['weight_g_used'], 262);
      expect(body['volume_ml'], isNull);
    });

    testWidgets('seeds the calculator from the plan and stores the volume', (
      tester,
    ) async {
      final administrations = MockAdministrationsRepo();
      when(() => administrations.create(any())).thenAnswer(
        (_) async =>
            const MedicationAdministration(id: 'ad1', caseId: 'c1', drug: 'x'),
      );

      await pumpSheet(
        tester,
        administrations,
        // A prescription that carries its rate and the bottle's strength.
        const Medication(
          id: 'm1',
          caseId: 'c1',
          drug: 'Baytril',
          doseUnit: 'mg',
          doseRate: 20,
          concentrationPerMl: 15,
        ),
      );

      await tester.tap(find.text('Dose calculator'));
      await tester.pumpAndSettle();

      // Nothing to type: both numbers came from the plan.
      expect(find.text('0.3493 ml'), findsOneWidget);
      expect(find.text('20 mg/kg × 262 g = 5.24 mg'), findsOneWidget);

      final apply = find.widgetWithText(FilledButton, 'Use as dose');
      await tester.ensureVisible(apply);
      await tester.tap(apply);
      await tester.pumpAndSettle();

      final save = find.widgetWithText(FilledButton, 'Save');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();

      final body =
          verify(() => administrations.create(captureAny())).captured.single
              as Map<String, dynamic>;
      expect(body['dose'], 5.24);
      expect(body['weight_g_used'], 262);
      expect(body['volume_ml'], 0.3493);
    });

    testWidgets('drops the derivation when the dose is typed over', (
      tester,
    ) async {
      final administrations = MockAdministrationsRepo();
      when(() => administrations.create(any())).thenAnswer(
        (_) async =>
            const MedicationAdministration(id: 'ad1', caseId: 'c1', drug: 'x'),
      );

      await pumpSheet(
        tester,
        administrations,
        const Medication(
          id: 'm1',
          caseId: 'c1',
          drug: 'Baytril',
          doseUnit: 'mg',
          doseRate: 20,
        ),
      );

      await tester.tap(find.text('Dose calculator'));
      await tester.pumpAndSettle();
      final apply = find.widgetWithText(FilledButton, 'Use as dose');
      await tester.ensureVisible(apply);
      await tester.tap(apply);
      await tester.pumpAndSettle();

      // Overriding the calculated amount makes the derivation a lie, so it is
      // not stored against the hand-typed number.
      final doseField = find.widgetWithText(TextField, 'Dose');
      await tester.ensureVisible(doseField);
      await tester.enterText(doseField, '4');
      await tester.pumpAndSettle();

      final save = find.widgetWithText(FilledButton, 'Save');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();

      final body =
          verify(() => administrations.create(captureAny())).captured.single
              as Map<String, dynamic>;
      expect(body['dose'], 4);
      expect(body['weight_g_used'], isNull);
      expect(body['volume_ml'], isNull);
    });
  });
}
