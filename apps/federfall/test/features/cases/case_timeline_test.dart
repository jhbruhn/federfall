import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/case_timeline.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart' hide Finder;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockJournalRepo extends Mock implements PbJournalRepository {}

class MockWeightsRepo extends Mock implements PbWeightsRepository {}

class MockCaseConditionsRepo extends Mock
    implements PbCaseConditionsRepository {}

class MockMedicationsRepo extends Mock implements PbMedicationsRepository {}

class MockAdministrationsRepo extends Mock
    implements PbMedicationAdministrationsRepository {}

class MockMarkingsRepo extends Mock implements PbMarkingsRepository {}

class MockPlacementsRepo extends Mock implements PbPlacementsRepository {}

class MockDispositionsRepo extends Mock implements PbDispositionsRepository {}

class MockFollowUpsRepo extends Mock implements PbFollowUpsRepository {}

class MockExamsRepo extends Mock implements PbExamsRepository {}

class MockExamFindingsRepo extends Mock implements PbExamFindingsRepository {}

void main() {
  late MockJournalRepo journal;
  late MockWeightsRepo weights;
  late MockCaseConditionsRepo caseConditions;
  late MockMedicationsRepo medications;
  late MockAdministrationsRepo administrations;
  late MockMarkingsRepo markings;
  late MockPlacementsRepo placements;
  late MockDispositionsRepo dispositions;
  late MockFollowUpsRepo followUps;
  late MockExamsRepo exams;
  late MockExamFindingsRepo examFindings;

  setUp(() {
    journal = MockJournalRepo();
    weights = MockWeightsRepo();
    caseConditions = MockCaseConditionsRepo();
    medications = MockMedicationsRepo();
    administrations = MockAdministrationsRepo();
    markings = MockMarkingsRepo();
    placements = MockPlacementsRepo();
    dispositions = MockDispositionsRepo();
    followUps = MockFollowUpsRepo();
    exams = MockExamsRepo();
    examFindings = MockExamFindingsRepo();
    when(() => weights.forCase(any())).thenAnswer((_) async => []);
    when(() => caseConditions.forCase(any())).thenAnswer((_) async => []);
    when(() => medications.forCase(any())).thenAnswer((_) async => []);
    when(() => administrations.forCase(any())).thenAnswer((_) async => []);
    when(() => markings.forAnimal(any())).thenAnswer((_) async => []);
    when(() => placements.forCase(any())).thenAnswer((_) async => []);
    when(() => dispositions.forCase(any())).thenAnswer((_) async => []);
    when(() => followUps.forCase(any())).thenAnswer((_) async => []);
    when(() => exams.forCase(any())).thenAnswer((_) async => []);
    when(() => examFindings.forCase(any())).thenAnswer((_) async => []);
  });

  Future<void> pump(WidgetTester tester, Case medicalCase) async {
    final container = ProviderContainer(
      overrides: [
        journalRepositoryProvider.overrideWith((ref) async => journal),
        weightsRepositoryProvider.overrideWith((ref) async => weights),
        caseConditionsRepositoryProvider
            .overrideWith((ref) async => caseConditions),
        medicationsRepositoryProvider
            .overrideWith((ref) async => medications),
        medicationAdministrationsRepositoryProvider
            .overrideWith((ref) async => administrations),
        markingsRepositoryProvider.overrideWith((ref) async => markings),
        placementsRepositoryProvider
            .overrideWith((ref) async => placements),
        dispositionsRepositoryProvider
            .overrideWith((ref) async => dispositions),
        followUpsRepositoryProvider.overrideWith((ref) async => followUps),
        examsRepositoryProvider.overrideWith((ref) async => exams),
        examFindingsRepositoryProvider
            .overrideWith((ref) async => examFindings),
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
          home: Scaffold(
            body: SingleChildScrollView(
              child: CaseTimeline(medicalCase: medicalCase),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('interleaves journal entries and milestones newest-first',
      (tester) async {
    when(() => journal.forCase('c1')).thenAnswer(
      (_) async => [
        JournalEntry(
          id: 'j1',
          caseId: 'c1',
          text: 'Mid entry',
          entryAt: DateTime.utc(2026, 6, 21),
        ),
      ],
    );

    final medicalCase = Case(
      id: 'c1',
      animal: 'a1',
      admittedAt: DateTime.utc(2026, 6, 20),
      created: DateTime.utc(2026, 6, 22),
    );
    await pump(tester, medicalCase);

    // All three live in one list (not split into Journal vs Timeline).
    expect(find.text('Case opened'), findsOneWidget); // 06-22, newest
    expect(find.text('Mid entry'), findsOneWidget); // 06-21
    expect(find.text('Admitted'), findsOneWidget); // 06-20, oldest

    // Verify the vertical order: opened above the journal entry above admitted.
    final opened = tester.getTopLeft(find.text('Case opened')).dy;
    final entry = tester.getTopLeft(find.text('Mid entry')).dy;
    final admitted = tester.getTopLeft(find.text('Admitted')).dy;
    expect(opened, lessThan(entry));
    expect(entry, lessThan(admitted));
  });

  testWidgets('places weight measurements on the timeline', (tester) async {
    when(() => journal.forCase('c1')).thenAnswer((_) async => []);
    when(() => weights.forCase('c1')).thenAnswer(
      (_) async => [
        Weight(
          id: 'w1',
          animal: 'a1',
          caseId: 'c1',
          weightG: 248,
          measuredAt: DateTime.utc(2026, 6, 21),
        ),
      ],
    );

    await pump(tester, const Case(id: 'c1', animal: 'a1'));

    expect(find.text('248 g'), findsOneWidget);
  });

  testWidgets('places an exam with vitals and an abnormal finding',
      (tester) async {
    when(() => journal.forCase('c1')).thenAnswer((_) async => []);
    when(() => exams.forCase('c1')).thenAnswer(
      (_) async => [
        Exam(
          id: 'e1',
          caseId: 'c1',
          animal: 'a1',
          examinedAt: DateTime.utc(2026, 6, 21),
          bodyCondition: 3,
          hydration: Hydration.moderate,
        ),
      ],
    );
    when(() => examFindings.forCase('c1')).thenAnswer(
      (_) async => [
        const ExamFinding(
          id: 'f1',
          exam: 'e1',
          system: BodySystem.legsFeet,
          status: FindingStatus.abnormal,
          note: 'pododermatitis',
        ),
      ],
    );

    await pump(tester, const Case(id: 'c1', animal: 'a1'));

    expect(find.text('Exam'), findsOneWidget);
    expect(_richContaining('Body condition', '3/5'), findsOneWidget);
    expect(_richContaining('Legs & feet', 'pododermatitis'), findsOneWidget);
  });

  testWidgets('shows the empty state when nothing is on the timeline',
      (tester) async {
    when(() => journal.forCase('c1')).thenAnswer((_) async => []);

    await pump(tester, const Case(id: 'c1', animal: 'a1'));

    expect(find.text('No entries yet'), findsOneWidget);
  });
}

/// Matches a `Text.rich` labelled fact whose combined plain text contains both
/// [label] and [value] (the exam tile renders each across separate spans).
Finder _richContaining(String label, String value) => find.byWidgetPredicate(
      (w) =>
          w is RichText &&
          w.text.toPlainText().contains(label) &&
          w.text.toPlainText().contains(value),
    );
