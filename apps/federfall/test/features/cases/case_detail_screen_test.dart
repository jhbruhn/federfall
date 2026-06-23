import 'package:federfall/data/repository_providers.dart';
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

void main() {
  late MockCasesRepo cases;
  late MockAnimalsRepo animals;
  late MockFindersRepo finders;
  late MockJournalRepo journal;
  late MockWeightsRepo weights;

  final medicalCase = Case(
    id: 'c1',
    animal: 'a1',
    caseNumber: '2026-001',
    status: CaseStatus.inTreatment,
    ageClass: AgeClass.adult,
    reasonsForAdmission: const [AdmissionReason.injury],
    findLocation: 'Domplatz',
    intakeWeightG: 250,
    intakeNotes: 'thin but alert',
    finder: 'f1',
    foundAt: DateTime.utc(2026, 6, 20),
    admittedAt: DateTime.utc(2026, 6, 21),
    created: DateTime.utc(2026, 6, 21, 9),
  );

  setUp(() {
    cases = MockCasesRepo();
    animals = MockAnimalsRepo();
    finders = MockFindersRepo();
    journal = MockJournalRepo();
    weights = MockWeightsRepo();
    when(() => journal.forCase(any())).thenAnswer((_) async => []);
    when(() => weights.forCase(any())).thenAnswer((_) async => []);
    when(() => cases.getOne(any())).thenAnswer((_) async => medicalCase);
    when(() => animals.getOne(any())).thenAnswer(
      (_) async =>
          const Animal(id: 'a1', species: 'Stadttaube', name: 'Pauli'),
    );
    when(() => finders.getOne(any())).thenAnswer(
      (_) async => const Finder(id: 'f1', lastName: 'Klein', phone: '0151'),
    );
  });

  Future<void> pump(WidgetTester tester) async {
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
    expect(find.text('In treatment'), findsOneWidget);
  });

  testWidgets('shows the intake summary and the linked finder',
      (tester) async {
    await pump(tester);

    expect(find.text('Domplatz'), findsOneWidget);
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
}
