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

  test("the admission day is the DEVICE's, not UTC's", () {
    // federfall-s0wk: `admittedAt` arrives UTC (pbDate normalises with
    // `.toUtc()`) while the range comes from a date picker, i.e. local days.
    // Bucketing by the UTC day compared the two across zones — and the
    // dashboard's "intakes this year" tile resolves its boundary locally, so
    // the count and the list it opens disagreed on New Year's Eve.
    final offset = DateTime.now().timeZoneOffset;
    // Local New Year's midnight, as the server would have stored it.
    final admittedUtc = DateTime(2026).toUtc();

    final result = run(
      [_c('newyear', admittedAt: admittedUtc)],
      CaseQuery(
        admittedRange: DateTimeRange(
          start: DateTime(2026),
          end: DateTime(2026, 12, 31),
        ),
      ),
    );

    expect(_ids(result), ['newyear']);
    // East of Greenwich that instant is 2025 in UTC, which is the reading this
    // asserts against. A device on UTC cannot express the case at all —
    // flagged so a green run there is not mistaken for coverage.
    expect(
      offset == Duration.zero || admittedUtc.year == 2025,
      isTrue,
      reason: offset == Duration.zero
          ? 'device is on UTC: this test cannot distinguish the two readings'
          : 'expected the stored instant to fall in the previous UTC year',
    );
  });

  test('status filter keeps only the matching lifecycle status', () {
    final result = run([
      _c('care'),
      _c('ready', status: CaseStatus.readyForRelease),
    ], const CaseQuery(allScope: true, status: CaseStatus.readyForRelease));

    expect(_ids(result), ['ready']);
  });

  test('carer filter shows that carer instead of the mine/all scope', () {
    // The default scope is "mine", and a carer filter has to override it —
    // intersecting the two would yield nothing for every carer but the
    // signed-in one (federfall-9mit).
    final cases = [
      _c('mine'),
      _c('theirs', carer: 'other'),
      _c('third', carer: 'someone'),
    ];

    expect(_ids(run(cases, const CaseQuery(carer: 'other'))), ['theirs']);
    // …and it also narrows a query already widened to all cases.
    expect(
      _ids(run(cases, const CaseQuery(allScope: true, carer: 'other'))),
      ['theirs'],
    );
  });

  test('carer filter still respects the other facets', () {
    final result = run([
      _c('open', carer: 'other'),
      _c('closed', carer: 'other', status: CaseStatus.disposed),
    ], const CaseQuery(carer: 'other'));

    // The workload card counts OPEN cases, so its tap-through must land on the
    // browser's active default — the same number it showed.
    expect(_ids(result), ['open']);
  });

  test('a carer facet counts instead of the scope it supersedes', () {
    const mine = CaseQuery();
    expect(mine.activeFacetCount, 0);
    expect(const CaseQuery(allScope: true).activeFacetCount, 1);
    expect(const CaseQuery(carer: 'other').activeFacetCount, 1);
    // Not 2: the scope toggle is inert while a carer is named, so badging both
    // would count a filter the user cannot see.
    expect(
      const CaseQuery(allScope: true, carer: 'other').activeFacetCount,
      1,
    );
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
      'carer': 'u123',
      'year': '2025',
    });

    expect(q.allScope, isTrue);
    expect(q.activity, CaseActivity.all);
    expect(q.status, CaseStatus.readyForRelease);
    expect(q.outcome, DispositionType.placedInAviary);
    expect(q.condition, 'Katzenbiss');
    expect(q.carer, 'u123');
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

  test('copyWith clears the carer facet without touching the others', () {
    const q = CaseQuery(carer: 'u123', condition: 'Katzenbiss');

    expect(q.copyWith(clearCarer: true).carer, isNull);
    expect(q.copyWith(clearCarer: true).condition, 'Katzenbiss');
    expect(q.copyWith(carer: 'u456').carer, 'u456');
  });

  test('the carer facet takes part in equality', () {
    expect(const CaseQuery(carer: 'a'), isNot(const CaseQuery(carer: 'b')));
    expect(const CaseQuery(carer: 'a'), isNot(const CaseQuery()));
    expect(const CaseQuery(carer: 'a'), const CaseQuery(carer: 'a'));
  });

  test('CaseQuery.fromParams falls back to defaults for empty params', () {
    expect(CaseQuery.fromParams(const {}), const CaseQuery());
  });
}
