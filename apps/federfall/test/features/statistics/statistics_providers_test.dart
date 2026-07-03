import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/statistics/statistics_providers.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockCasesRepo extends Mock implements PbCasesRepository {}

class MockDispositionsRepo extends Mock implements PbDispositionsRepository {}

class MockCaseConditionsRepo extends Mock
    implements PbCaseConditionsRepository {}

class MockAnimalsRepo extends Mock implements PbAnimalsRepository {}

class MockConditionsRepo extends Mock implements PbConditionsRepository {}

Case _case(String id, {String animal = 'a1', DateTime? admittedAt}) =>
    Case(id: id, animal: animal, admittedAt: admittedAt);

Disposition _disp(
  String id,
  String caseId,
  DispositionType type, {
  DateTime? at,
}) => Disposition(id: id, caseId: caseId, type: type, disposedAt: at);

CaseCondition _cc(String id, {String? condition, String? freeText}) =>
    CaseCondition(
      id: id,
      caseId: 'c1',
      condition: condition,
      freeText: freeText,
    );

void main() {
  Statistics run({
    List<Case> cases = const [],
    List<Disposition> dispositions = const [],
    List<CaseCondition> caseConditions = const [],
    Map<String, String> species = const {},
    Map<String, String> conditions = const {},
  }) => computeStatistics(
    cases: cases,
    dispositions: dispositions,
    caseConditions: caseConditions,
    speciesByAnimal: species,
    conditionLabels: conditions,
  );

  test('counts total and open cases (no terminal disposition)', () {
    final s = run(
      cases: [_case('c1'), _case('c2'), _case('c3')],
      dispositions: [_disp('d1', 'c1', DispositionType.released)],
    );
    expect(s.totalCases, 3);
    expect(s.openCases, 2);
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

  test('condition breakdown resolves labels and falls back to free text', () {
    final s = run(
      caseConditions: [
        _cc('1', condition: 'cond1'),
        _cc('2', condition: 'cond1'),
        _cc('3', freeText: 'Unbekannt'),
      ],
      conditions: {'cond1': 'Trichomoniasis'},
    );
    final byLabel = {for (final c in s.byCondition) c.label: c.count};
    expect(byLabel['Trichomoniasis'], 2);
    expect(byLabel['Unbekannt'], 1);
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
      final caseConditions = MockCaseConditionsRepo();
      final animals = MockAnimalsRepo();
      final conditions = MockConditionsRepo();

      when(cases.list).thenAnswer(
        (_) async => [_case('c1'), _case('c2')],
      );
      when(dispositions.list).thenAnswer(
        (_) async => [_disp('d1', 'c1', DispositionType.released)],
      );
      when(
        caseConditions.list,
      ).thenAnswer((_) async => [_cc('1', condition: 'cond1')]);
      when(animals.list).thenAnswer(
        (_) async => const [Animal(id: 'a1', species: 'Columba livia')],
      );
      when(conditions.list).thenAnswer(
        (_) async => const [
          Condition(id: 'cond1', label: 'Trichomoniasis'),
        ],
      );

      final container = ProviderContainer(
        overrides: [
          casesRepositoryProvider.overrideWith((ref) async => cases),
          dispositionsRepositoryProvider.overrideWith(
            (ref) async => dispositions,
          ),
          caseConditionsRepositoryProvider.overrideWith(
            (ref) async => caseConditions,
          ),
          animalsRepositoryProvider.overrideWith((ref) async => animals),
          conditionsRepositoryProvider.overrideWith((ref) async => conditions),
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
