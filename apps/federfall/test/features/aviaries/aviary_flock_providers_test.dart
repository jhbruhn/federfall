import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/aviaries/aviary_flock_providers.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockJournalRepo extends Mock implements PbJournalRepository {}

class MockAviaryStaysRepo extends Mock implements PbAviaryStaysRepository {}

class MockAnimalsRepo extends Mock implements PbAnimalsRepository {}

class MockCasesRepo extends Mock implements PbCasesRepository {}

class MockCaseConditionsRepo extends Mock
    implements PbCaseConditionsRepository {}

void main() {
  late MockJournalRepo journal;
  late MockAviaryStaysRepo stays;
  late MockAnimalsRepo animals;
  late MockCasesRepo cases;
  late MockCaseConditionsRepo conditions;
  late ProviderContainer container;

  setUp(() {
    journal = MockJournalRepo();
    stays = MockAviaryStaysRepo();
    animals = MockAnimalsRepo();
    cases = MockCasesRepo();
    conditions = MockCaseConditionsRepo();
    container = ProviderContainer(
      overrides: [
        journalRepositoryProvider.overrideWith((ref) async => journal),
        aviaryStaysRepositoryProvider.overrideWith((ref) async => stays),
        animalsRepositoryProvider.overrideWith((ref) async => animals),
        casesRepositoryProvider.overrideWith((ref) async => cases),
        caseConditionsRepositoryProvider.overrideWith(
          (ref) async => conditions,
        ),
      ],
    );
    addTearDown(container.dispose);
  });

  test('aviaryJournal delegates to the repository', () async {
    when(() => journal.forAviary('av1')).thenAnswer(
      (_) async => const [JournalEntry(id: 'j1', aviary: 'av1', text: 'x')],
    );

    final result = await container.read(aviaryJournalProvider('av1').future);

    expect(result, hasLength(1));
  });

  group('aviaryHealthRollup', () {
    test('no residency history -> empty, no further queries', () async {
      when(() => stays.forAviary('av1')).thenAnswer((_) async => const []);

      final result = await container.read(
        aviaryHealthRollupProvider('av1').future,
      );

      expect(result, isEmpty);
      verifyNever(() => animals.byIds(any()));
    });

    test('includes a condition dated inside the residency window', () async {
      when(() => stays.forAviary('av1')).thenAnswer(
        (_) async => [
          AviaryStay(
            id: 's1',
            animal: 'a1',
            aviary: 'av1',
            startedAt: DateTime.utc(2026),
            endedAt: DateTime.utc(2026, 2),
          ),
        ],
      );
      when(() => animals.byIds(any())).thenAnswer(
        (_) async => const [Animal(id: 'a1', species: 'Taube', name: 'Pip')],
      );
      when(
        () => cases.byAnimals(any()),
      ).thenAnswer((_) async => const [Case(id: 'case1', animal: 'a1')]);
      when(() => conditions.byCases(any())).thenAnswer(
        (_) async => [
          CaseCondition(
            id: 'cc1',
            caseId: 'case1',
            freeText: 'Trichomoniasis',
            onsetDate: DateTime.utc(2026, 1, 15),
          ),
        ],
      );

      final result = await container.read(
        aviaryHealthRollupProvider('av1').future,
      );

      expect(result, hasLength(1));
      expect(result.single.condition.freeText, 'Trichomoniasis');
      expect(result.single.animal?.name, 'Pip');
    });

    test('excludes a condition dated outside the residency window', () async {
      when(() => stays.forAviary('av1')).thenAnswer(
        (_) async => [
          AviaryStay(
            id: 's1',
            animal: 'a1',
            aviary: 'av1',
            startedAt: DateTime.utc(2026),
            endedAt: DateTime.utc(2026, 2),
          ),
        ],
      );
      when(
        () => animals.byIds(any()),
      ).thenAnswer((_) async => const [Animal(id: 'a1', species: 'Taube')]);
      when(
        () => cases.byAnimals(any()),
      ).thenAnswer((_) async => const [Case(id: 'case1', animal: 'a1')]);
      when(() => conditions.byCases(any())).thenAnswer(
        (_) async => [
          // Diagnosed well after this residency ended.
          CaseCondition(
            id: 'cc1',
            caseId: 'case1',
            freeText: 'Later illness',
            onsetDate: DateTime.utc(2026, 6),
          ),
        ],
      );

      final result = await container.read(
        aviaryHealthRollupProvider('av1').future,
      );

      expect(result, isEmpty);
    });

    test(
      'a resident that moved aviaries keeps its history attributed correctly',
      () async {
        // Same animal, two aviaries, two disjoint stay windows.
        when(() => stays.forAviary('av1')).thenAnswer(
          (_) async => [
            AviaryStay(
              id: 's1',
              animal: 'a1',
              aviary: 'av1',
              startedAt: DateTime.utc(2026),
              endedAt: DateTime.utc(2026, 2),
            ),
          ],
        );
        when(
          () => animals.byIds(any()),
        ).thenAnswer((_) async => const [Animal(id: 'a1', species: 'Taube')]);
        when(
          () => cases.byAnimals(any()),
        ).thenAnswer((_) async => const [Case(id: 'case1', animal: 'a1')]);
        when(() => conditions.byCases(any())).thenAnswer(
          (_) async => [
            // While resident in av1.
            CaseCondition(
              id: 'cc1',
              caseId: 'case1',
              freeText: 'While in av1',
              onsetDate: DateTime.utc(2026, 1, 10),
            ),
            // After moving to a different aviary — must not show under av1.
            CaseCondition(
              id: 'cc2',
              caseId: 'case1',
              freeText: 'While in av2',
              onsetDate: DateTime.utc(2026, 3, 10),
            ),
          ],
        );

        final result = await container.read(
          aviaryHealthRollupProvider('av1').future,
        );

        expect(result, hasLength(1));
        expect(result.single.condition.freeText, 'While in av1');
      },
    );

    test(
      "fetches every resident animal's cases in ONE call, not one per "
      'animal (no N+1)',
      () async {
        when(() => stays.forAviary('av1')).thenAnswer(
          (_) async => [
            AviaryStay(
              id: 's1',
              animal: 'a1',
              aviary: 'av1',
              startedAt: DateTime.utc(2026),
            ),
            AviaryStay(
              id: 's2',
              animal: 'a2',
              aviary: 'av1',
              startedAt: DateTime.utc(2026),
            ),
            AviaryStay(
              id: 's3',
              animal: 'a3',
              aviary: 'av1',
              startedAt: DateTime.utc(2026),
            ),
          ],
        );
        when(() => animals.byIds(any())).thenAnswer((_) async => const []);
        when(
          () => cases.byAnimals(any()),
        ).thenAnswer((_) async => const []);
        when(
          () => conditions.byCases(any()),
        ).thenAnswer((_) async => const []);

        await container.read(aviaryHealthRollupProvider('av1').future);

        verify(() => cases.byAnimals(any())).called(1);
        verifyNever(() => cases.forAnimal(any()));
      },
    );

    test('an ongoing (unended) residency covers up to now', () async {
      when(() => stays.forAviary('av1')).thenAnswer(
        (_) async => [
          AviaryStay(
            id: 's1',
            animal: 'a1',
            aviary: 'av1',
            startedAt: DateTime.utc(2020),
          ),
        ],
      );
      when(
        () => animals.byIds(any()),
      ).thenAnswer((_) async => const [Animal(id: 'a1', species: 'Taube')]);
      when(
        () => cases.byAnimals(any()),
      ).thenAnswer((_) async => const [Case(id: 'case1', animal: 'a1')]);
      when(() => conditions.byCases(any())).thenAnswer(
        (_) async => [
          CaseCondition(
            id: 'cc1',
            caseId: 'case1',
            freeText: 'Recent',
            onsetDate: DateTime.now().toUtc(),
          ),
        ],
      );

      final result = await container.read(
        aviaryHealthRollupProvider('av1').future,
      );

      expect(result, hasLength(1));
    });
  });
}
