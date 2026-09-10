import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/features/cases/conditions/conditions_providers.dart';
import 'package:federfall/features/cases/current_treatment_card.dart';
import 'package:federfall/features/cases/medications/medication_routes_providers.dart';
import 'package:federfall/features/cases/medications/medications_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart' hide Finder;
import 'package:mocktail/mocktail.dart';

class MockMedicationsRepo extends Mock implements PbMedicationsRepository {}

const _codes = [
  Condition(id: 'cond1', label: 'Fracture'),
  Condition(id: 'cond2', label: 'Psittacosis', isNotifiable: true),
];

void main() {
  setUpAll(() => registerFallbackValue(<String, dynamic>{}));

  late MockMedicationsRepo medications;

  setUp(() => medications = MockMedicationsRepo());

  Future<void> pump(
    WidgetTester tester, {
    List<CaseCondition> conditions = const [],
    List<Medication> plans = const [],
    Map<String, DateTime> nextDue = const {},
    bool canEdit = true,
  }) async {
    final container = ProviderContainer(
      overrides: [
        caseConditionsForCaseProvider(
          'c1',
        ).overrideWith((_) async => conditions),
        medicationsForCaseProvider('c1').overrideWith((_) async => plans),
        nextDoseByMedicationProvider('c1').overrideWith((_) async => nextDue),
        canEditCaseProvider('c1').overrideWith((_) async => canEdit),
        conditionsProvider.overrideWith((_) async => _codes),
        medicationsRepositoryProvider.overrideWith((_) async => medications),
        medicationRoutesProvider.overrideWith(
          (_) async => const [
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
          theme: AppTheme.light,
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: CurrentTreatmentCard(caseId: 'c1')),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('CurrentTreatmentCard', () {
    testWidgets('renders nothing at all when there is no treatment', (
      tester,
    ) async {
      await pump(tester);
      // Not an empty card: a bird on nothing must not cost a slot to say so.
      expect(find.byType(Card), findsNothing);
      expect(find.text('Current treatment'), findsNothing);
    });

    testWidgets('states the running course, its regimen and its next dose', (
      tester,
    ) async {
      final due = DateTime.now().add(const Duration(hours: 3));
      await pump(
        tester,
        plans: const [
          Medication(
            id: 'm1',
            caseId: 'c1',
            drug: 'Baytril',
            dose: 0.3,
            doseUnit: 'ml',
            route: 'mr_subcut',
            frequencyKind: MedicationFrequencyKind.scheduled,
            intervalHours: 12,
          ),
        ],
        nextDue: {'m1': due},
      );

      expect(find.text('Current treatment'), findsOneWidget);
      expect(find.text('Baytril'), findsOneWidget);
      expect(find.text('0.3 ml · Subcutaneous · Twice daily'), findsOneWidget);
      expect(find.textContaining('Next dose:'), findsOneWidget);
    });

    testWidgets('an overdue dose is error-coloured', (tester) async {
      final scheme = AppTheme.light.colorScheme;
      await pump(
        tester,
        plans: const [Medication(id: 'm1', caseId: 'c1', drug: 'Baytril')],
        nextDue: {'m1': DateTime.now().subtract(const Duration(hours: 5))},
      );
      final line = tester.widget<Text>(find.textContaining('Next dose:'));
      expect(line.style?.color, scheme.error);
    });

    testWidgets('a course with no computed next dose still shows', (
      tester,
    ) async {
      // An as-needed prescription has no next_due and is still running; the
      // line is omitted rather than guessed at.
      await pump(
        tester,
        plans: const [Medication(id: 'm1', caseId: 'c1', drug: 'Metacam')],
      );
      expect(find.text('Metacam'), findsOneWidget);
      expect(find.textContaining('Next dose:'), findsNothing);
    });

    testWidgets('an ended course is gone, a future end is still running', (
      tester,
    ) async {
      await pump(
        tester,
        plans: [
          Medication(
            id: 'm1',
            caseId: 'c1',
            drug: 'Baytril',
            endedAt: DateTime.now().subtract(const Duration(days: 1)),
          ),
          Medication(
            id: 'm2',
            caseId: 'c1',
            drug: 'Metacam',
            endedAt: DateTime.now().add(const Duration(days: 3)),
          ),
        ],
      );
      expect(find.text('Baytril'), findsNothing);
      expect(find.text('Metacam'), findsOneWidget);
    });

    testWidgets('only unresolved diagnoses, and notifiable keeps its badge', (
      tester,
    ) async {
      await pump(
        tester,
        conditions: [
          const CaseCondition(id: 'x1', caseId: 'c1', condition: 'cond1'),
          const CaseCondition(id: 'x2', caseId: 'c1', condition: 'cond2'),
          CaseCondition(
            id: 'x3',
            caseId: 'c1',
            freeText: 'Dehydration',
            resolvedDate: DateTime.utc(2026),
          ),
        ],
      );
      expect(find.text('Fracture'), findsOneWidget);
      expect(find.textContaining('Psittacosis'), findsOneWidget);
      // The badge rides on the chip: a notifiable diagnosis is a legal
      // obligation, so it must not read like any other label here.
      expect(find.textContaining('Notifiable'), findsOneWidget);
      expect(find.text('Dehydration'), findsNothing);
    });

    testWidgets('a read-only viewer gets the facts and neither verb', (
      tester,
    ) async {
      await pump(
        tester,
        plans: const [Medication(id: 'm1', caseId: 'c1', drug: 'Baytril')],
        canEdit: false,
      );
      expect(find.text('Baytril'), findsOneWidget);
      expect(find.byIcon(Icons.vaccines_outlined), findsNothing);
      expect(find.byIcon(Icons.stop_circle_outlined), findsNothing);
    });

    testWidgets('a course can be stopped from the card itself', (
      tester,
    ) async {
      // The same act the timeline tile offers, through the same
      // confirmStopMedication — this card is where a carer establishes what
      // the bird is on, so it is where they realise a course should end.
      when(
        () => medications.update('m1', any()),
      ).thenAnswer(
        (_) async => const Medication(id: 'm1', caseId: 'c1', drug: 'Baytril'),
      );

      await pump(
        tester,
        plans: const [Medication(id: 'm1', caseId: 'c1', drug: 'Baytril')],
      );

      await tester.tap(find.byIcon(Icons.stop_circle_outlined));
      await tester.pumpAndSettle();
      // Confirmed, not immediate: nothing here shows that stopping takes the
      // course off the worklist and the dose reminders with it.
      expect(find.text('Stop medication?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Stop'));
      await tester.pumpAndSettle();

      final data =
          verify(() => medications.update('m1', captureAny())).captured.single
              as Map<String, dynamic>;
      expect(DateTime.parse(data['ended_at']! as String).isUtc, isTrue);
      verifyNever(() => medications.delete(any()));
    });

    testWidgets('cancelling the confirmation leaves the course running', (
      tester,
    ) async {
      await pump(
        tester,
        plans: const [Medication(id: 'm1', caseId: 'c1', drug: 'Baytril')],
      );
      await tester.tap(find.byIcon(Icons.stop_circle_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      verifyNever(() => medications.update(any(), any()));
    });
  });
}
