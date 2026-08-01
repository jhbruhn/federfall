import 'package:federfall/features/cases/case_facets.dart';
import 'package:federfall/features/cases/cases_browser.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_test/flutter_test.dart';

Case _c(
  String id, {
  String animal = 'a1',
  String? number,
  String carer = 'me',
  CaseStatus status = CaseStatus.inCare,
  DateTime? admittedAt,
}) => Case(
  id: id,
  animal: animal,
  caseNumber: number,
  activeCarer: carer,
  status: status,
  admittedAt: admittedAt,
);

const _animals = {
  'a1': Animal(id: 'a1', species: 'Columba livia', name: 'Pip'),
  'a2': Animal(id: 'a2', species: 'Streptopelia decaocto', name: 'Fritz'),
};

List<String> _ids(List<Case> cases) => cases.map((c) => c.id).toList();

void main() {
  List<Case> run(List<Case> cases, CaseQuery query) =>
      filterCases(cases, _animals, myUserId: 'me', query: query);

  test("default scope keeps only the user's own active cases", () {
    final result = run([
      _c('mine'),
      _c('theirs', carer: 'other'),
      _c('closed', status: CaseStatus.disposed),
    ], const CaseQuery());

    expect(_ids(result), ['mine']);
  });

  test('all scope widens to every accessible case', () {
    final result = run([
      _c('mine'),
      _c('theirs', carer: 'other'),
    ], const CaseQuery(allScope: true));

    expect(_ids(result), ['mine', 'theirs']);
  });

  test('closed activity shows only disposed cases', () {
    final result = run([
      _c('open'),
      _c('done', status: CaseStatus.disposed),
    ], const CaseQuery(activity: CaseActivity.closed));

    expect(_ids(result), ['done']);
  });

  test('all activity keeps active and closed', () {
    final result = run([
      _c('open'),
      _c('done', status: CaseStatus.disposed),
    ], const CaseQuery(activity: CaseActivity.all));

    expect(_ids(result), ['open', 'done']);
  });

  test("species filter matches the case's animal", () {
    final result = run([
      _c('pigeon'),
      _c('dove', animal: 'a2'),
    ], const CaseQuery(species: 'Streptopelia decaocto'));

    expect(_ids(result), ['dove']);
  });

  test('text search matches case number or animal name', () {
    final cases = [
      _c('byNumber', number: '2026-042'),
      _c('byName', animal: 'a2'),
    ];

    expect(_ids(run(cases, const CaseQuery(text: '042'))), ['byNumber']);
    expect(_ids(run(cases, const CaseQuery(text: 'fritz'))), ['byName']);
  });

  test("text search matches the animal's active marking codes", () {
    final cases = [
      _c('ringed'),
      _c('plain', animal: 'a2'),
    ];
    final result = filterCases(
      cases,
      _animals,
      myUserId: 'me',
      query: const CaseQuery(text: 'de-2024'),
      codesByAnimal: const {
        'a1': ['DE-2024-0815'],
      },
    );

    expect(_ids(result), ['ringed']);
  });

  test('date range filters by admission day, excluding undated cases', () {
    final result = run(
      [
        _c('in', admittedAt: DateTime(2026, 6, 10)),
        _c('out', admittedAt: DateTime(2026, 1, 20)),
        _c('undated'),
      ],
      CaseQuery(
        admittedRange: DateTimeRange(
          start: DateTime(2026, 6, 2),
          end: DateTime(2026, 6, 30),
        ),
      ),
    );

    expect(_ids(result), ['in']);
  });

  test('status filter keeps only the matching lifecycle status', () {
    final result = run([
      _c('care'),
      _c('ready', status: CaseStatus.readyForRelease),
    ], const CaseQuery(allScope: true, status: CaseStatus.readyForRelease));

    expect(_ids(result), ['ready']);
  });

  test('outcome filter matches the terminal disposition (federfall-5puj)', () {
    final result = filterCases(
      [_c('released'), _c('died'), _c('open')],
      _animals,
      myUserId: 'me',
      query: const CaseQuery(
        activity: CaseActivity.all,
        outcome: DispositionType.released,
      ),
      facets: const CaseFacets(
        outcomeByCase: {
          'released': DispositionType.released,
          'died': DispositionType.died,
        },
      ),
    );

    expect(_ids(result), ['released']);
  });

  test('condition filter matches a diagnosis label on the case', () {
    final result = filterCases(
      [_c('sick'), _c('hurt'), _c('none')],
      _animals,
      myUserId: 'me',
      query: const CaseQuery(condition: 'Trichomoniasis'),
      facets: const CaseFacets(
        conditionsByCase: {
          'sick': {'Trichomoniasis', 'Abmagerung'},
          'hurt': {'Katzenbiss'},
        },
      ),
    );

    expect(_ids(result), ['sick']);
  });

  test('an outcome/condition query matches nothing without facets loaded', () {
    // The default empty facets are only correct for a query that doesn't need
    // them — filtering with them anyway must not silently pass every case.
    final result = run([
      _c('a'),
      _c('b'),
    ], const CaseQuery(outcome: DispositionType.released));

    expect(result, isEmpty);
  });

  test('needsFacets flags exactly the queries that read the extra loads', () {
    expect(const CaseQuery().needsFacets, isFalse);
    expect(const CaseQuery(species: 'Columba livia').needsFacets, isFalse);
    expect(
      const CaseQuery(outcome: DispositionType.died).needsFacets,
      isTrue,
    );
    expect(const CaseQuery(condition: 'Katzenbiss').needsFacets, isTrue);
  });

  test('CaseQuery.fromParams seeds a deep-linked filter', () {
    final q = CaseQuery.fromParams(const {
      'scope': 'all',
      'activity': 'all',
      'status': 'ready_for_release',
      'outcome': 'placed_in_aviary',
      'condition': 'Katzenbiss',
      'year': '2025',
    });

    expect(q.allScope, isTrue);
    expect(q.activity, CaseActivity.all);
    expect(q.status, CaseStatus.readyForRelease);
    expect(q.outcome, DispositionType.placedInAviary);
    expect(q.condition, 'Katzenbiss');
    expect(q.admittedRange?.start.year, 2025);
    expect(q.admittedRange?.end.year, 2025);
  });

  test('copyWith clears the outcome and condition facets individually', () {
    const q = CaseQuery(
      outcome: DispositionType.died,
      condition: 'Katzenbiss',
    );

    expect(q.activeFacetCount, 2);
    expect(q.copyWith(clearOutcome: true).outcome, isNull);
    expect(q.copyWith(clearOutcome: true).condition, 'Katzenbiss');
    expect(q.copyWith(clearCondition: true).condition, isNull);
    expect(q.copyWith(clearCondition: true).outcome, DispositionType.died);
  });

  test('CaseQuery.fromParams falls back to defaults for empty params', () {
    expect(CaseQuery.fromParams(const {}), const CaseQuery());
  });
}
