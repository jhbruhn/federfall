import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/animals/animals_providers.dart';
import 'package:federfall/features/cases/case_detail_screen.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart' hide Finder;
import 'package:mocktail/mocktail.dart';

class MockCasesRepo extends Mock implements PbCasesRepository {}

class MockAnimalsRepo extends Mock implements PbAnimalsRepository {}

class MockFindersRepo extends Mock implements PbFindersRepository {}

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
  setUpAll(() => registerFallbackValue(<String, dynamic>{}));

  late MockCasesRepo cases;
  late MockAnimalsRepo animals;
  late MockFindersRepo finders;
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

  final medicalCase = Case(
    id: 'c1',
    animal: 'a1',
    caseNumber: '2026-001',
    status: CaseStatus.inCare,
    ageClass: AgeClass.adult,
    reasonsForAdmission: const [AdmissionReason.injury],
    findLocation: 'Domplatz',
    intakeWeightG: 250,
    intakeNotes: 'thin but alert',
    finder: 'f1',
    foundAt: DateTime.utc(2026, 6, 20),
    admittedAt: DateTime.utc(2026, 6, 21),
    quarantineUntil: DateTime.utc(2026, 7, 5),
    created: DateTime.utc(2026, 6, 21, 9),
  );

  setUp(() {
    cases = MockCasesRepo();
    animals = MockAnimalsRepo();
    finders = MockFindersRepo();
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
    when(() => followUps.forCase(any())).thenAnswer((_) async => []);
    when(() => exams.forCase(any())).thenAnswer((_) async => []);
    when(() => examFindings.forCase(any())).thenAnswer((_) async => []);
    when(() => placements.forCase(any())).thenAnswer((_) async => []);
    when(() => dispositions.forCase(any())).thenAnswer((_) async => []);
    when(() => journal.forCase(any())).thenAnswer((_) async => []);
    when(() => weights.forCase(any())).thenAnswer((_) async => []);
    when(() => caseConditions.forCase(any())).thenAnswer((_) async => []);
    when(() => medications.forCase(any())).thenAnswer((_) async => []);
    when(() => administrations.forCase(any())).thenAnswer((_) async => []);
    when(() => markings.forAnimal(any())).thenAnswer((_) async => []);
    when(() => cases.getOne(any())).thenAnswer((_) async => medicalCase);
    when(() => animals.getOne(any())).thenAnswer(
      (_) async =>
          const Animal(id: 'a1', species: 'Stadttaube', name: 'Pauli'),
    );
    when(() => finders.getOne(any())).thenAnswer(
      (_) async => const Finder(id: 'f1', lastName: 'Klein', phone: '0151'),
    );
  });

  Future<void> pump(
    WidgetTester tester, {
    AnimalLifetime? lifetime,
    AppUser? currentUser,
  }) async {
    // A tall surface so the whole scroll view (incl. the timeline) is built.
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [
        casesRepositoryProvider.overrideWith((ref) async => cases),
        animalsRepositoryProvider.overrideWith((ref) async => animals),
        findersRepositoryProvider.overrideWith((ref) async => finders),
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
        if (lifetime != null)
          animalLifetimeProvider('a1').overrideWith((ref) async => lifetime),
        if (currentUser != null)
          currentUserProvider.overrideWith((ref) async => currentUser),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: CaseDetailScreen(caseId: 'c1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders a name-first header with species and case number',
      (tester) async {
    await pump(tester);

    expect(find.text('Pauli'), findsOneWidget);
    expect(find.text('Stadttaube · 2026-001'), findsOneWidget);
    expect(find.text('In care'), findsOneWidget);
  });

  testWidgets('shows the intake summary and the linked finder',
      (tester) async {
    await pump(tester);

    expect(find.text('Domplatz'), findsOneWidget);
    expect(find.text('Quarantine until'), findsOneWidget);
    expect(find.text('250 g'), findsOneWidget);
    expect(find.text('thin but alert'), findsOneWidget);
    expect(find.text('Klein · 0151'), findsOneWidget);
  });

  testWidgets('lists intake milestones in the History tab', (tester) async {
    await pump(tester);

    // The chronology lives behind the History tab.
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();

    expect(find.text('Admitted'), findsOneWidget);
    expect(find.text('Case opened'), findsOneWidget);
  });

  testWidgets("Overview lists the animal's other cases", (tester) async {
    await pump(
      tester,
      lifetime: const AnimalLifetime(
        animal: Animal(id: 'a1', species: 'Stadttaube', name: 'Pauli'),
        markings: [],
        cases: [
          // The current case plus an older, accessible one.
          CaseSummary(id: 'c1', animal: 'a1', caseNumber: '2026-001'),
          CaseSummary(
            id: 'c0',
            animal: 'a1',
            caseNumber: '2025-009',
            status: CaseStatus.disposed,
          ),
        ],
        accessibleCaseIds: {'c1', 'c0'},
      ),
    );

    expect(find.text('Other cases'), findsOneWidget);
    // The other case shows; the current case (c1) is excluded from the list.
    expect(find.text('2025-009'), findsOneWidget);
  });

  testWidgets('Overview hides prior cases when there are none',
      (tester) async {
    await pump(
      tester,
      lifetime: const AnimalLifetime(
        animal: Animal(id: 'a1', species: 'Stadttaube', name: 'Pauli'),
        markings: [],
        cases: [CaseSummary(id: 'c1', animal: 'a1', caseNumber: '2026-001')],
        accessibleCaseIds: {'c1'},
      ),
    );

    expect(find.text('Other cases'), findsNothing);
  });

  testWidgets('a supervisor can mark an in-care case ready for release',
      (tester) async {
    when(() => cases.update(any(), any())).thenAnswer(
      (_) async => medicalCase,
    );

    await pump(
      tester,
      currentUser: const AppUser(
        id: 'sup1',
        email: 'sup@x.org',
        role: UserRole.supervisor,
      ),
    );

    await tester.tap(find.text('Mark ready for release'));
    await tester.pumpAndSettle();

    final data =
        verify(() => cases.update('c1', captureAny())).captured.single
            as Map<String, dynamic>;
    expect(data['status'], 'ready_for_release');
  });

  testWidgets('a read-only viewer sees no status control', (tester) async {
    await pump(
      tester,
      currentUser: const AppUser(
        id: 'other',
        email: 'other@x.org',
        role: UserRole.carer,
      ),
    );

    expect(find.text('Mark ready for release'), findsNothing);
  });
}
