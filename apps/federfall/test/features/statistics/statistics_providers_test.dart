import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/statistics/statistics_providers.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockCasesRepo extends Mock implements PbCasesRepository {}

class MockDispositionsRepo extends Mock implements PbDispositionsRepository {}

class MockAnimalsRepo extends Mock implements PbAnimalsRepository {}

class MockConditionLabelsRepo extends Mock
    implements PbConditionLabelsRepository {}

Case _case(String id, {String animal = 'a1', DateTime? admittedAt}) =>
    Case(id: id, animal: animal, admittedAt: admittedAt);

Disposition _disp(
  String id,
  String caseId,
  DispositionType type, {
  DateTime? at,
}) => Disposition(id: id, caseId: caseId, type: type, disposedAt: at);

ConditionLabel _cl(String label, int caseCount) =>
    ConditionLabel(id: label, label: label, caseCount: caseCount);

void main() {
  Statistics run({
    List<Case> cases = const [],
    List<Disposition> dispositions = const [],
    List<ConditionLabel> recordedConditions = const [],
    Map<String, String> species = const {},
  }) => computeStatistics(
    cases: cases,
    dispositions: dispositions,
    recordedConditions: recordedConditions,
    speciesByAnimal: species,
  );

  test('counts total and open cases (no terminal disposition)', () {
    final s = run(
      cases: [_case('c1'), _case('c2'), _case('c3')],
      dispositions: [_disp('d1', 'c1', DispositionType.released)],
    );
    expect(s.totalCases, 3);
    expect(s.openCases, 2);
  });

  test('reports the years that have intakes, newest first', () {
    // federfall-dk0c: the annual-report export offers exactly these as periods,
    // so a duplicate year collapses, a case with no admission date contributes
    // nothing, and the order is the one the picker shows.
    final s = run(
      cases: [
        _case('c1', admittedAt: DateTime(2024, 5, 4)),
        _case('c2', admittedAt: DateTime(2026)),
        _case('c3', admittedAt: DateTime(2024, 11, 30)),
        _case('c4'),
      ],
    );
    expect(s.intakeYears, [2026, 2024]);
  });

  test('outcome breakdown uses the latest disposition per case', () {
    final s = run(
      cases: [_case('c1'), _case('c2')],
      dispositions: [
        // c1 was re-dispositioned: died then (later) released → released wins.
        _disp('d1', 'c1', DispositionType.died, at: DateTime(2026, 2, 3)),
        _disp('d2', 'c1', DispositionType.released, at: DateTime(2026, 3, 4)),
        _disp('d3', 'c2', DispositionType.euthanized, at: DateTime(2026, 2, 5)),
      ],
    );
    final byType = {for (final o in s.outcomes) o.type: o.count};
    expect(byType[DispositionType.released], 1);
    expect(byType[DispositionType.euthanized], 1);
    expect(byType.containsKey(DispositionType.died), isFalse);
  });

  test('species breakdown counts cases, ranked by frequency', () {
    final s = run(
      cases: [
        _case('c1'),
        _case('c2', animal: 'a2'),
        _case('c3', animal: 'a3'),
      ],
      species: {
        'a1': 'Columba livia',
        'a2': 'Columba livia',
        'a3': 'Streptopelia decaocto',
      },
    );
    expect(s.bySpecies.first.label, 'Columba livia');
    expect(s.bySpecies.first.count, 2);
    expect(s.bySpecies.last.count, 1);
  });

  test('condition breakdown ranks the counts the view already made', () {
    // Resolving code-list vs free-text labels and counting DISTINCT cases per
    // label is the `condition_labels` view's job now (federfall-ye5e, asserted
    // against a live PocketBase in backend/pocketbase/tests/test_rules.py).
    // What is left here is the ranking.
    final s = run(
      recordedConditions: [_cl('Unbekannt', 1), _cl('Trichomoniasis', 2)],
    );

    expect(
      [for (final c in s.byCondition) c.label],
      [
        'Trichomoniasis',
        'Unbekannt',
      ],
    );
    expect(s.byCondition.first.count, 2);
  });

  test('average time in care over disposed cases with both dates', () {
    final s = run(
      cases: [
        _case('c1', admittedAt: DateTime(2026, 2, 2)),
        _case('c2', admittedAt: DateTime(2026, 2, 2)),
      ],
      dispositions: [
        _disp('d1', 'c1', DispositionType.released, at: DateTime(2026, 2, 12)),
        _disp('d2', 'c2', DispositionType.died, at: DateTime(2026, 2, 22)),
      ],
    );
    // 10 and 20 days → mean 15.
    expect(s.avgTimeInCareDays, closeTo(15, 0.01));
  });

  test('average is null when no disposed case has both dates', () {
    final s = run(cases: [_case('c1', admittedAt: DateTime(2026, 2, 2))]);
    expect(s.avgTimeInCareDays, isNull);
  });

  test(
    'statistics provider loads and aggregates across repositories',
    () async {
      final cases = MockCasesRepo();
      final dispositions = MockDispositionsRepo();
      final animals = MockAnimalsRepo();
      final conditionLabels = MockConditionLabelsRepo();

      when(cases.list).thenAnswer(
        (_) async => [_case('c1'), _case('c2')],
      );
      when(dispositions.list).thenAnswer(
        (_) async => [_disp('d1', 'c1', DispositionType.released)],
      );
      when(animals.list).thenAnswer(
        (_) async => const [Animal(id: 'a1', species: 'Columba livia')],
      );
      when(conditionLabels.all).thenAnswer(
        (_) async => [_cl('Trichomoniasis', 1)],
      );

      final container = ProviderContainer(
        overrides: [
          casesRepositoryProvider.overrideWith((ref) async => cases),
          dispositionsRepositoryProvider.overrideWith(
            (ref) async => dispositions,
          ),
          animalsRepositoryProvider.overrideWith((ref) async => animals),
          conditionLabelsRepositoryProvider.overrideWith(
            (ref) async => conditionLabels,
          ),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(statisticsProvider.future);

      expect(result.totalCases, 2);
      expect(result.openCases, 1);
      expect(result.bySpecies.single.label, 'Columba livia');
      expect(result.byCondition.single.label, 'Trichomoniasis');
    },
  );
}
