import 'package:federfall/features/cases/case_facets.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter_test/flutter_test.dart';

Disposition _disp(
  String id,
  String caseId,
  DispositionType? type, {
  DateTime? at,
}) => Disposition(id: id, caseId: caseId, type: type, disposedAt: at);

CaseCondition _cc(
  String id,
  String caseId, {
  String? condition,
  String? freeText,
}) => CaseCondition(
  id: id,
  caseId: caseId,
  condition: condition,
  freeText: freeText,
);

void main() {
  CaseFacets build({
    List<Disposition> dispositions = const [],
    List<CaseCondition> caseConditions = const [],
    Map<String, String> conditionLabels = const {},
  }) => buildCaseFacets(
    dispositions: dispositions,
    caseConditions: caseConditions,
    conditionLabels: conditionLabels,
  );

  test(
    'outcome is the latest disposition when a case was re-dispositioned',
    () {
      final facets = build(
        dispositions: [
          _disp(
            'd1',
            'c1',
            DispositionType.placedInAviary,
            at: DateTime(2026, 3),
          ),
          _disp('d2', 'c1', DispositionType.released, at: DateTime(2026, 5)),
        ],
      );

      expect(facets.outcomeByCase, {'c1': DispositionType.released});
    },
  );

  test('a disposition of an unknown type is left out of the outcomes', () {
    // It can be counted in the statistics as "unknown", but there is no filter
    // value that names it, so the browser must not claim to resolve it.
    final facets = build(dispositions: [_disp('d1', 'c1', null)]);

    expect(facets.outcomeByCase, isEmpty);
  });

  test(
    'conditions resolve through the code list and fall back to free text',
    () {
      final facets = build(
        caseConditions: [
          _cc('1', 'c1', condition: 'cond1'),
          _cc('2', 'c1', freeText: 'Unbekannt'),
          _cc('3', 'c2', condition: 'cond1'),
        ],
        conditionLabels: {'cond1': 'Trichomoniasis'},
      );

      expect(facets.conditionsByCase, {
        'c1': {'Trichomoniasis', 'Unbekannt'},
        'c2': {'Trichomoniasis'},
      });
    },
  );

  test('a free-text diagnosis buckets with its code-list twin', () {
    // Same label, one typed by hand and one picked from the list — the label
    // is the key precisely so these are the same diagnosis.
    final facets = build(
      caseConditions: [
        _cc('1', 'c1', condition: 'cond1'),
        _cc('2', 'c2', freeText: 'Katzenbiss'),
      ],
      conditionLabels: {'cond1': 'Katzenbiss'},
    );

    expect(facets.conditionsByCase['c1'], {'Katzenbiss'});
    expect(facets.conditionsByCase['c2'], {'Katzenbiss'});
  });

  test(
    'a diagnosis with neither a code-list entry nor free text is dropped',
    () {
      final facets = build(
        caseConditions: [
          _cc('1', 'c1'),
          _cc('2', 'c1', freeText: ''),
        ],
      );

      expect(facets.conditionsByCase, isEmpty);
    },
  );
}
