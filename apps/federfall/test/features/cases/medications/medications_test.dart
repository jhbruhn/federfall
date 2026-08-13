import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/medications/administration_sheet.dart';
import 'package:federfall/features/cases/medications/batch_administration_sheet.dart';
import 'package:federfall/features/cases/medications/cycle_preview.dart';
import 'package:federfall/features/cases/medications/medication_products_providers.dart';
import 'package:federfall/features/cases/medications/medication_routes_providers.dart';
import 'package:federfall/features/cases/medications/medication_tiles.dart';
import 'package:federfall/features/cases/medications/medications_providers.dart';
import 'package:federfall/features/cases/medications/prescription_sheet.dart';
import 'package:federfall/features/cases/weights/weights_providers.dart';
import 'package:federfall/features/worklist/worklist.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockMedicationsRepo extends Mock implements PbMedicationsRepository {}

class MockAdministrationsRepo extends Mock
    implements PbMedicationAdministrationsRepository {}

class MockWeightsRepo extends Mock implements PbWeightsRepository {}

/// Two other open cases the signed-in carer holds, for the group picker. The
/// second bird is unnamed, so its row falls back to the species — the same
/// title the worklist builds.
const _others = [
  PrescribableCase(
    caseRecord: Case(id: 'c2', animal: 'a2', caseNumber: 'C-2'),
    animal: Animal(id: 'a2', species: 'Rock pigeon', name: 'Bruno'),
  ),
  PrescribableCase(
    caseRecord: Case(id: 'c3', animal: 'a3', caseNumber: 'C-3'),
    animal: Animal(id: 'a3', species: 'Rock pigeon'),
  ),
];

void main() {
  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(<String>[]);
  });

  late MockMedicationsRepo medications;
  late MockAdministrationsRepo administrations;
  late MockWeightsRepo weightsRepo;

  setUp(() {
    medications = MockMedicationsRepo();
    administrations = MockAdministrationsRepo();
    weightsRepo = MockWeightsRepo();
  });

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    List<Weight> weights = const [],
    List<MedicationProduct> catalogue = const [],
    List<PrescribableCase> others = const [],
  }) async {
    final container = ProviderContainer(
      overrides: [
        weightsForCaseProvider('c1').overrideWith((ref) async => weights),
        prescribableCasesProvider('c1').overrideWith((ref) async => others),
        weightsRepositoryProvider.overrideWith((ref) async => weightsRepo),
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
          MedicationProduct(
            id: 'p2',
            label: 'Medikament 2',
            doseUnit: 'ml',
            doseRate: 0.5,
          ),
        ],
      );

      Future<void> pick(String label) async {
        await tester.tap(
          find.byType(DropdownButtonFormField<MedicationProduct>),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
      }

      String fieldText(String label) =>
          tester
              .widget<TextField>(find.widgetWithText(TextField, label))
              .controller
              ?.text ??
          '';

      // A fluid entry first: dosed in ml/kg, with nothing to draw up.
      await pick('Medikament 2');
      expect(fieldText('Unit'), 'ml');
      expect(fieldText('Dose'), '0.5');
      expect(fieldText('Product concentration'), isEmpty);

      await pick('Medikament 1');

      // Switching entries replaces every field the catalogue owns. Keeping the
      // fluid's "ml" here would have priced the dose in the wrong unit, and a
      // leftover strength would draw up the volume of another drug.
      expect(fieldText('Unit'), 'mg');
      expect(fieldText('Dose'), '20');
      expect(fieldText('Product concentration'), '15');
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

    testWidgets('a cycle stores both day counts and ends on the last '
        'giving day', (tester) async {
      when(() => medications.create(any())).thenAnswer(
        (_) async => const Medication(id: 'm1', caseId: 'c1', drug: 'x'),
      );

      await pump(tester, const PrescriptionSheet(caseId: 'c1'));
      await tester.enterText(find.byType(TextField).first, 'Panacur');
      await tester.ensureVisible(find.text('Cyclic schedule'));
      await tester.tap(find.text('Cyclic schedule'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Days on'),
        '5',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Days off'),
        '2',
      );
      await tester.enterText(find.widgetWithText(TextFormField, 'Cycles'), '3');
      await tester.pumpAndSettle();

      final started = tester
          .widget<DateField>(find.widgetWithText(DateField, 'Start'))
          .value!;
      // Three rounds of 5-on/2-off end after the LAST giving day, so the
      // trailing pause is dropped: 3 × 7 − 2 = 19 days, not 21.
      expect(
        tester
            .widget<DateField>(find.widgetWithText(DateField, 'Active until'))
            .value,
        started.add(const Duration(days: 19)),
      );

      await save(tester);
      final body =
          verify(() => medications.create(captureAny())).captured.single
              as Map<String, dynamic>;
      expect(body['cycle_on_days'], 5);
      expect(body['cycle_off_days'], 2);
    });

    testWidgets('a catalogue entry pours its course into an end date', (
      tester,
    ) async {
      when(() => medications.create(any())).thenAnswer(
        (_) async => const Medication(id: 'm1', caseId: 'c1', drug: 'x'),
      );

      await pump(
        tester,
        const PrescriptionSheet(caseId: 'c1'),
        catalogue: const [
          MedicationProduct(
            id: 'p1',
            label: 'Panacur',
            doseUnit: 'mg',
            frequencyKind: MedicationFrequencyKind.scheduled,
            intervalHours: 12,
            cycleOnDays: 5,
            cycleOffDays: 2,
            cycleRepeats: 3,
          ),
        ],
      );
      await tester.tap(find.byType(DropdownButtonFormField<MedicationProduct>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Panacur').last);
      await tester.pumpAndSettle();

      // The count lives on the entry; the END DATE is derived here, against
      // this bird's own start — the catalogue never sees that date.
      final started = tester
          .widget<DateField>(find.widgetWithText(DateField, 'Start'))
          .value!;
      expect(
        tester
            .widget<DateField>(find.widgetWithText(DateField, 'Active until'))
            .value,
        started.add(const Duration(days: 19)),
      );

      await save(tester);
      final body =
          verify(() => medications.create(captureAny())).captured.single
              as Map<String, dynamic>;
      expect(body['cycle_on_days'], 5);
      expect(body['cycle_off_days'], 2);
      // The prescription stores dates, never a count (1700000091).
      expect(body.containsKey('cycle_repeats'), isFalse);
    });

    testWidgets('the cycle preview draws the whole course, once both halves '
        'are typed', (tester) async {
      await pump(tester, const PrescriptionSheet(caseId: 'c1'));
      await tester.ensureVisible(find.text('Cyclic schedule'));
      await tester.tap(find.text('Cyclic schedule'));
      await tester.pumpAndSettle();

      // Half a pair has no shape to draw.
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Days on'),
        '5',
      );
      await tester.pumpAndSettle();
      expect(find.byType(MedicationCyclePreview), findsNothing);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Days off'),
        '2',
      );
      await tester.pumpAndSettle();

      int marks({required bool giving}) => tester
          .widgetList<CycleDayMark>(find.byType(CycleDayMark))
          .where((m) => m.giving == giving)
          .length;

      // No end date yet: two rounds drawn to show the rhythm restarting, then
      // an ellipsis saying it keeps going.
      expect(find.text('5 days on / 2 days off'), findsOneWidget);
      expect(marks(giving: true), 10);
      expect(marks(giving: false), 4);
      expect(find.text('…'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextFormField, 'Cycles'), '3');
      await tester.pumpAndSettle();

      // The WHOLE course, not one round with a multiplier: 3 × 5 giving days,
      // and only 2 × 2 pause days because the last round ends on its final
      // giving day — the same day `ended_at` lands on.
      expect(marks(giving: true), 15);
      expect(marks(giving: false), 4);
      expect(find.text('× 3'), findsNothing);
      expect(find.text('…'), findsNothing);
      expect(find.text('5 days on / 2 days off · 3 cycles'), findsOneWidget);
    });

    testWidgets('a course too long to draw degrades to one round', (
      tester,
    ) async {
      await pump(tester, const PrescriptionSheet(caseId: 'c1'));
      await tester.ensureVisible(find.text('Cyclic schedule'));
      await tester.tap(find.text('Cyclic schedule'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Days on'),
        '10',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Days off'),
        '10',
      );
      await tester.enterText(find.widgetWithText(TextFormField, 'Cycles'), '5');
      await tester.pumpAndSettle();

      // 5 × 20 − 10 = 90 days is a wall of dots; one round plus the count is
      // what stays readable.
      expect(find.byType(CycleDayMark), findsNWidgets(20));
      expect(find.text('× 5'), findsOneWidget);
    });

    testWidgets('a plan without a cycle sends null, never half a pair', (
      tester,
    ) async {
      when(() => medications.create(any())).thenAnswer(
        (_) async => const Medication(id: 'm1', caseId: 'c1', drug: 'x'),
      );

      await pump(tester, const PrescriptionSheet(caseId: 'c1'));
      await tester.enterText(find.byType(TextField).first, 'Baytril');
      await save(tester);

      final body =
          verify(() => medications.create(captureAny())).captured.single
              as Map<String, dynamic>;
      expect(body['cycle_on_days'], isNull);
      expect(body['cycle_off_days'], isNull);
    });

    testWidgets('editing a cycled plan derives its cycle count back', (
      tester,
    ) async {
      final started = DateTime.utc(2026, 6, 1, 8);
      await pump(
        tester,
        PrescriptionSheet(
          caseId: 'c1',
          plan: Medication(
            id: 'm1',
            caseId: 'c1',
            drug: 'Panacur',
            frequencyKind: MedicationFrequencyKind.scheduled,
            intervalHours: 12,
            cycleOnDays: 5,
            cycleOffDays: 2,
            startedAt: started,
            endedAt: started.add(const Duration(days: 19)),
          ),
        ),
      );

      // The count is not stored — it is read back out of the two dates and the
      // rhythm, so the form shows the "3" that produced this end date.
      expect(
        tester
            .widget<TextFormField>(
              find.widgetWithText(TextFormField, 'Cycles'),
            )
            .controller
            ?.text,
        '3',
      );
    });

    testWidgets('editing seeds both dates in local time', (tester) async {
      // The server hands back UTC; DateField formats what it is given and
      // pickDateTime re-seeds from it, so a UTC value would both display and
      // re-store the wrong instant. Asserted as `isUtc`, not as text, so it
      // holds in a UTC-clocked CI too.
      final started = DateTime.utc(2026, 3, 14, 23, 30);
      final ended = DateTime.utc(2026, 3, 20, 23, 30);

      await pump(
        tester,
        PrescriptionSheet(
          caseId: 'c1',
          plan: Medication(
            id: 'm1',
            caseId: 'c1',
            drug: 'Baytril',
            startedAt: started,
            endedAt: ended,
          ),
        ),
      );

      DateTime? valueOf(String label) =>
          tester.widget<DateField>(find.widgetWithText(DateField, label)).value;

      expect(valueOf('Start')!.isUtc, isFalse);
      expect(valueOf('Start')!.isAtSameMomentAs(started), isTrue);
      expect(valueOf('Active until')!.isUtc, isFalse);
      expect(valueOf('Active until')!.isAtSameMomentAs(ended), isTrue);
    });
  });

  // The give/pause pair is validated AS a pair. Validating each half on its own
  // made the switch a trap: turn it on, think better of it, and the form could
  // not be saved at all until you found the switch again.
  group('PrescriptionSheet cycle pair', () {
    Future<void> turnOnCycle(WidgetTester tester) async {
      await tester.ensureVisible(find.text('Cyclic schedule'));
      await tester.tap(find.text('Cyclic schedule'));
      await tester.pumpAndSettle();
    }

    testWidgets('the switch on with both halves empty saves as no rhythm', (
      tester,
    ) async {
      when(() => medications.create(any())).thenAnswer(
        (_) async => const Medication(id: 'm1', caseId: 'c1', drug: 'x'),
      );

      await pump(tester, const PrescriptionSheet(caseId: 'c1'));
      await tester.enterText(find.byType(TextField).first, 'Baycox');
      await turnOnCycle(tester);

      // It says what the empty pair will do rather than blocking the save.
      expect(find.text('Left empty, no rhythm is saved.'), findsOneWidget);
      await save(tester);

      final body =
          verify(() => medications.create(captureAny())).captured.single
              as Map<String, dynamic>;
      expect(body['cycle_on_days'], isNull);
      expect(body['cycle_off_days'], isNull);
    });

    testWidgets('zero is refused, and the message says where the exit is', (
      tester,
    ) async {
      await pump(tester, const PrescriptionSheet(caseId: 'c1'));
      await tester.enterText(find.byType(TextField).first, 'Baycox');
      await turnOnCycle(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Days on'), '5');
      await tester.enterText(find.widgetWithText(TextField, 'Days off'), '0');
      await tester.pumpAndSettle();
      await save(tester);

      expect(
        find.text(
          'At least 1 day — switch the rhythm off for a course with no pause.',
        ),
        findsOneWidget,
      );
      verifyNever(() => medications.create(any()));
    });

    testWidgets('one half filled makes the other required', (tester) async {
      await pump(tester, const PrescriptionSheet(caseId: 'c1'));
      await tester.enterText(find.byType(TextField).first, 'Baycox');
      await turnOnCycle(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Days on'), '5');
      await tester.pumpAndSettle();
      await save(tester);

      expect(find.text('This field is required'), findsOneWidget);
      verifyNever(() => medications.create(any()));
    });

    testWidgets('clearing a filled pair is a way back out', (tester) async {
      // The actual report: the fields could not be emptied again, so a plan
      // that no longer wanted a rhythm could not be saved at all.
      when(() => medications.create(any())).thenAnswer(
        (_) async => const Medication(id: 'm1', caseId: 'c1', drug: 'x'),
      );

      await pump(tester, const PrescriptionSheet(caseId: 'c1'));
      await tester.enterText(find.byType(TextField).first, 'Baycox');
      await turnOnCycle(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Days on'), '5');
      await tester.enterText(find.widgetWithText(TextField, 'Days off'), '2');
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Days on'), '');
      await tester.enterText(find.widgetWithText(TextField, 'Days off'), '');
      await tester.pumpAndSettle();
      await save(tester);

      final body =
          verify(() => medications.create(captureAny())).captured.single
              as Map<String, dynamic>;
      expect(body['cycle_on_days'], isNull);
    });
  });

  // federfall-hqhg — nine birds on the same course is one decision, so it is
  // one write. The picker offers the carer's other open cases; ticking any of
  // them routes the save through the transactional endpoint instead of N
  // creates, and this sheet's own case rides along in the same batch.
  group('PrescriptionSheet group prescribing', () {
    Future<void> turnOnGroup(WidgetTester tester) async {
      await tester.ensureVisible(find.text('Also for other cases'));
      await tester.tap(find.text('Also for other cases'));
      await tester.pumpAndSettle();
    }

    testWidgets('one course reaches every ticked case in one request', (
      tester,
    ) async {
      when(
        () => medications.prescribeBatch(
          any(),
          any(),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      ).thenAnswer((_) async => 3);

      await pump(
        tester,
        const PrescriptionSheet(caseId: 'c1'),
        others: _others,
      );
      await tester.enterText(find.byType(TextField).first, 'Baycox');
      await turnOnGroup(tester);
      await tester.tap(find.text('C-2 · Bruno'));
      await tester.tap(find.text('C-3 · Rock pigeon'));
      await tester.pumpAndSettle();

      // The button counts the whole batch, this case included — three, not the
      // two that were ticked.
      final submit = find.widgetWithText(FilledButton, 'Add for 3 cases');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();

      final call = verify(
        () => medications.prescribeBatch(
          captureAny(),
          captureAny(),
          idempotencyKey: captureAny(named: 'idempotencyKey'),
        ),
      ).captured;
      expect(call[0], ['c1', 'c2', 'c3']);
      expect((call[1] as Map<String, dynamic>)['drug'], 'Baycox');
      // `case` and `org` are the server's to set on a batch, unlike a create.
      expect((call[1] as Map<String, dynamic>).containsKey('case'), isFalse);
      // A retry after a timeout must replay the committed batch, not double it.
      expect(call[2], isNotEmpty);
      verifyNever(() => medications.create(any()));
    });

    testWidgets('the group switch alone is not a batch', (tester) async {
      // Turning it on and ticking nobody means one prescription for this case.
      // The batch route would accept a single case, but going through it would
      // record the act as a group prescription in the audit log.
      when(() => medications.create(any())).thenAnswer(
        (_) async => const Medication(id: 'm1', caseId: 'c1', drug: 'x'),
      );

      await pump(
        tester,
        const PrescriptionSheet(caseId: 'c1'),
        others: _others,
      );
      await tester.enterText(find.byType(TextField).first, 'Baycox');
      await turnOnGroup(tester);
      await save(tester);

      verify(() => medications.create(any())).called(1);
      verifyNever(
        () => medications.prescribeBatch(
          any(),
          any(),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      );
    });

    testWidgets('unticking a case drops it from the batch', (tester) async {
      when(
        () => medications.prescribeBatch(
          any(),
          any(),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      ).thenAnswer((_) async => 2);

      await pump(
        tester,
        const PrescriptionSheet(caseId: 'c1'),
        others: _others,
      );
      await tester.enterText(find.byType(TextField).first, 'Baycox');
      await turnOnGroup(tester);
      await tester.tap(find.text('C-2 · Bruno'));
      await tester.tap(find.text('C-3 · Rock pigeon'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('C-3 · Rock pigeon'));
      await tester.pumpAndSettle();

      final submit = find.widgetWithText(FilledButton, 'Add for 2 cases');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();

      final cases = verify(
        () => medications.prescribeBatch(
          captureAny(),
          any(),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      ).captured.single;
      expect(cases, ['c1', 'c2']);
    });

    testWidgets('switching the group off forgets what was ticked', (
      tester,
    ) async {
      // A hidden selection that a later switch-on restores would put birds on a
      // course the carer had visibly taken them off.
      when(() => medications.create(any())).thenAnswer(
        (_) async => const Medication(id: 'm1', caseId: 'c1', drug: 'x'),
      );

      await pump(
        tester,
        const PrescriptionSheet(caseId: 'c1'),
        others: _others,
      );
      await tester.enterText(find.byType(TextField).first, 'Baycox');
      await turnOnGroup(tester);
      await tester.tap(find.text('C-2 · Bruno'));
      await tester.pumpAndSettle();
      await turnOnGroup(tester);
      await turnOnGroup(tester);

      expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);
      await save(tester);
      verify(() => medications.create(any())).called(1);
    });

    testWidgets('editing a plan offers no group at all', (tester) async {
      // A course diverges the moment one bird comes off it, so there is no
      // batch edit — nine rows are nine prescriptions.
      await pump(
        tester,
        const PrescriptionSheet(
          caseId: 'c1',
          plan: Medication(id: 'm1', caseId: 'c1', drug: 'Baycox'),
        ),
        others: _others,
      );

      expect(find.text('Also for other cases'), findsNothing);
    });

    testWidgets('a carer with no other open cases is told so', (tester) async {
      await pump(tester, const PrescriptionSheet(caseId: 'c1'));
      await turnOnGroup(tester);

      expect(
        find.text('You are not carrying any other open cases.'),
        findsOneWidget,
      );
    });
  });

  // federfall-o3gz — giving one drug to a group is one act, but the AMOUNT is
  // per bird: a rate is prescribed per kilogram, so nine birds on one course
  // get nine different numbers.
  group('BatchAdministrationSheet', () {
    /// A due for [caseId] on a per-kilogram plan.
    WorklistItem due(String caseId, {String drug = 'Ronidazol'}) =>
        WorklistItem(
          kind: WorklistKind.medicationDue,
          caseId: caseId,
          dueAt: DateTime(2026, 8, 12, 7),
          severity: WorklistSeverity.overdue,
          caseNumber: 'C-$caseId',
          drug: drug,
          medication: Medication(
            id: 'plan-$caseId',
            caseId: caseId,
            drug: drug,
            doseRate: 10,
            doseUnit: 'mg',
            concentrationPerMl: 100,
          ),
        );

    Weight weight(
      String caseId,
      double grams, {
      Duration age = Duration.zero,
    }) => Weight(
      id: 'w-$caseId',
      animal: 'a-$caseId',
      caseId: caseId,
      weightG: grams,
      measuredAt: DateTime.now().subtract(age),
    );

    Future<void> pumpRound(
      WidgetTester tester,
      List<WorklistItem> dues, {
      List<Weight> weights = const [],
      bool failWeights = false,
    }) async {
      if (failWeights) {
        when(() => weightsRepo.byCases(any())).thenThrow(
          const RepositoryException('nope', kind: RepositoryErrorKind.network),
        );
      } else {
        when(() => weightsRepo.byCases(any())).thenAnswer((_) async => weights);
      }
      await pump(
        tester,
        BatchAdministrationSheet(
          group: MedicationDueGroup(drug: dues.first.drug!, items: dues),
        ),
      );
    }

    testWidgets('each bird gets the amount its OWN weight derives', (
      tester,
    ) async {
      when(
        () => administrations.administerBatch(
          any(),
          any(),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      ).thenAnswer((_) async => 2);

      await pumpRound(
        tester,
        [due('c1'), due('c2')],
        weights: [weight('c1', 245), weight('c2', 300)],
      );

      // 10 mg/kg over 245 g and 300 g — two courses of one plan, two numbers.
      expect(find.text('2.45'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);

      final submit = find.widgetWithText(FilledButton, 'Log 2 doses');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();

      final call = verify(
        () => administrations.administerBatch(
          captureAny(),
          captureAny(),
          idempotencyKey: captureAny(named: 'idempotencyKey'),
        ),
      ).captured;
      final doses = call[0] as List<Map<String, dynamic>>;
      expect(doses.map((d) => d['medication']), ['plan-c1', 'plan-c2']);
      expect(doses.map((d) => d['dose']), [2.45, 3.0]);
      // The derivation rides along, so the record can say which weight and
      // which volume produced the amount.
      expect(doses.first['weight_g_used'], 245);
      expect(doses.first['volume_ml'], 0.0245);
      // Only the moment is shared.
      expect((call[1] as Map<String, dynamic>)['administered_at'], isNotEmpty);
      expect(call[2], isNotEmpty);
    });

    testWidgets('a stale weight prefills nothing and says why', (tester) async {
      // The one place a batch could silently dose nine birds off a number
      // nobody checked — so it refuses to guess, exactly like the single-dose
      // calculator.
      await pumpRound(
        tester,
        [due('c1'), due('c2')],
        weights: [
          weight('c1', 245),
          weight('c2', 300, age: const Duration(days: 5)),
        ],
      );

      expect(find.text('2.45'), findsOneWidget);
      expect(find.text('3'), findsNothing);
      expect(
        find.textContaining('is too old', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('a bird never weighed says so instead of going blank', (
      tester,
    ) async {
      await pumpRound(
        tester,
        [due('c1'), due('c2')],
        weights: [
          weight('c1', 245),
        ],
      );

      expect(
        find.text('No weight on record — enter the amount'),
        findsOneWidget,
      );
    });

    testWidgets('unticking a bird drops it from the round', (tester) async {
      when(
        () => administrations.administerBatch(
          any(),
          any(),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      ).thenAnswer((_) async => 1);

      await pumpRound(
        tester,
        [due('c1'), due('c2')],
        weights: [weight('c1', 245), weight('c2', 300)],
      );
      await tester.tap(find.text('C-c2'));
      await tester.pumpAndSettle();

      final submit = find.widgetWithText(FilledButton, 'Log 1 dose');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();

      final doses =
          verify(
                () => administrations.administerBatch(
                  captureAny(),
                  any(),
                  idempotencyKey: any(named: 'idempotencyKey'),
                ),
              ).captured.single
              as List<Map<String, dynamic>>;
      expect(doses.map((d) => d['medication']), ['plan-c1']);
    });

    testWidgets('a failed weight fetch is stated, not silent', (tester) async {
      // Every rate-based prefill is missing because of it, and a blank dose
      // field with no explanation reads as "no dose needed".
      await pumpRound(tester, [due('c1'), due('c2')], failWeights: true);

      expect(
        find.text('Weights could not be loaded — enter the amounts yourself.'),
        findsOneWidget,
      );
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
      await tester.tap(find.widgetWithText(DestructiveActionButton, 'Delete'));
      await tester.pumpAndSettle();

      verify(() => administrations.delete('a1')).called(1);
    });
  });
}
