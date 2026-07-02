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

class MockQuarantineRepo extends Mock implements PbQuarantineRepository {}

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
  late MockQuarantineRepo quarantine;

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
    quarantine = MockQuarantineRepo();
    when(() => quarantine.forCase(any())).thenAnswer((_) async => []);
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

  Future<void> pump(
    WidgetTester tester,
    Case medicalCase, {
    bool canEdit = true,
  }) async {
    final container = ProviderContainer(
      overrides: [
        journalRepositoryProvider.overrideWith((ref) async => journal),
        weightsRepositoryProvider.overrideWith((ref) async => weights),
        caseConditionsRepositoryProvider.overrideWith(
          (ref) async => caseConditions,
        ),
        medicationsRepositoryProvider.overrideWith((ref) async => medications),
        medicationAdministrationsRepositoryProvider.overrideWith(
          (ref) async => administrations,
        ),
        markingsRepositoryProvider.overrideWith((ref) async => markings),
        placementsRepositoryProvider.overrideWith((ref) async => placements),
        dispositionsRepositoryProvider.overrideWith(
          (ref) async => dispositions,
        ),
        followUpsRepositoryProvider.overrideWith((ref) async => followUps),
        examsRepositoryProvider.overrideWith((ref) async => exams),
        examFindingsRepositoryProvider.overrideWith(
          (ref) async => examFindings,
        ),
        quarantineRepositoryProvider.overrideWith((ref) async => quarantine),
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
          // The timeline is its own lazy scrollable now — pump it directly as
          // the body (nesting it in another scroll view is unsupported).
          home: Scaffold(
            body: CaseTimeline(medicalCase: medicalCase, canEdit: canEdit),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('interleaves journal entries and milestones newest-first', (
    tester,
  ) async {
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

  testWidgets('orders a same-instant weight above the Admitted milestone', (
    tester,
  ) async {
    when(() => journal.forCase('c1')).thenAnswer((_) async => []);
    // The intake weight is measured at the admission time (new_case_screen),
    // so the two share an instant; the record sorts above the milestone
    // (deterministic tie-break, not the unstable order it had before).
    final instant = DateTime.utc(2026, 6, 20, 9);
    when(() => weights.forCase('c1')).thenAnswer(
      (_) async => [
        Weight(
          id: 'w1',
          animal: 'a1',
          caseId: 'c1',
          weightG: 250,
          measuredAt: instant,
        ),
      ],
    );

    await pump(tester, Case(id: 'c1', animal: 'a1', admittedAt: instant));

    final admitted = tester.getTopLeft(find.text('Admitted')).dy;
    final weight = tester.getTopLeft(find.text('250 g')).dy;
    expect(weight, lessThan(admitted));
  });

  testWidgets('places an exam with vitals and an abnormal finding', (
    tester,
  ) async {
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

  testWidgets('shows the empty state when nothing is on the timeline', (
    tester,
  ) async {
    when(() => journal.forCase('c1')).thenAnswer((_) async => []);

    await pump(tester, const Case(id: 'c1', animal: 'a1'));

    expect(find.text('No entries yet'), findsOneWidget);
  });

  testWidgets('an editable entry carries its overflow menu', (tester) async {
    when(() => journal.forCase('c1')).thenAnswer(
      (_) async => [
        JournalEntry(
          id: 'j1',
          caseId: 'c1',
          text: 'A note',
          entryAt: DateTime.utc(2026, 6, 21),
        ),
      ],
    );

    await pump(tester, const Case(id: 'c1', animal: 'a1'));

    expect(find.text('A note'), findsOneWidget);
    expect(find.byIcon(Icons.more_vert), findsOneWidget);
  });

  testWidgets('hides per-entry edit menus when the case is read-only', (
    tester,
  ) async {
    when(() => journal.forCase('c1')).thenAnswer(
      (_) async => [
        JournalEntry(
          id: 'j1',
          caseId: 'c1',
          text: 'A note',
          entryAt: DateTime.utc(2026, 6, 21),
        ),
      ],
    );

    await pump(tester, const Case(id: 'c1', animal: 'a1'), canEdit: false);

    // The content stays; only the write affordance is gone.
    expect(find.text('A note'), findsOneWidget);
    expect(find.byIcon(Icons.more_vert), findsNothing);
  });

  testWidgets('an ended quarantine shows both a started and an ended entry', (
    tester,
  ) async {
    when(() => journal.forCase('c1')).thenAnswer((_) async => []);
    // Imposed two months ago, ended one month ago — both dates are in the past.
    when(() => quarantine.forCase('c1')).thenAnswer(
      (_) async => [
        Quarantine(
          id: 'q1',
          caseId: 'c1',
          setAt: DateTime.utc(2026, 4, 20),
          until: DateTime.utc(2026, 5, 4),
        ),
      ],
    );

    await pump(tester, const Case(id: 'c1', animal: 'a1'));

    // Two entries: the imposition and a separate "ended" marker at its end.
    expect(find.textContaining('Quarantine until'), findsOneWidget);
    expect(find.text('Quarantine ended'), findsOneWidget);

    // The started entry sits above the ended marker (newest-first: the end date
    // is more recent than the start).
    final ended = tester.getTopLeft(find.text('Quarantine ended')).dy;
    final started = tester
        .getTopLeft(find.textContaining('Quarantine until'))
        .dy;
    expect(ended, lessThan(started));
  });

  testWidgets('an active quarantine shows only the started entry', (
    tester,
  ) async {
    when(() => journal.forCase('c1')).thenAnswer((_) async => []);
    when(() => quarantine.forCase('c1')).thenAnswer(
      (_) async => [
        Quarantine(
          id: 'q1',
          caseId: 'c1',
          setAt: DateTime.utc(2026, 6, 20),
          until: DateTime.utc(2099, 6, 20), // far future — not yet ended
        ),
      ],
    );

    await pump(tester, const Case(id: 'c1', animal: 'a1'));

    expect(find.textContaining('Quarantine until'), findsOneWidget);
    expect(find.text('Quarantine ended'), findsNothing);
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
