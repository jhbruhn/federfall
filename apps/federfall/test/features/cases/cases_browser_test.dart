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

  test('date range filters by admission day, excluding undated cases', () {
    final result = run([
      _c('in', admittedAt: DateTime(2026, 6, 10)),
      _c('out', admittedAt: DateTime(2026, 1, 20)),
      _c('undated'),
    ], CaseQuery(
      admittedRange: DateTimeRange(
        start: DateTime(2026, 6, 2),
        end: DateTime(2026, 6, 30),
      ),
    ));

    expect(_ids(result), ['in']);
  });

  test('status filter keeps only the matching lifecycle status', () {
    final result = run([
      _c('care'),
      _c('ready', status: CaseStatus.readyForRelease),
    ], const CaseQuery(allScope: true, status: CaseStatus.readyForRelease));

    expect(_ids(result), ['ready']);
  });

  test('CaseQuery.fromParams seeds a deep-linked filter', () {
    final q = CaseQuery.fromParams(const {
      'scope': 'all',
      'activity': 'all',
      'status': 'ready_for_release',
      'year': '2025',
    });

    expect(q.allScope, isTrue);
    expect(q.activity, CaseActivity.all);
    expect(q.status, CaseStatus.readyForRelease);
    expect(q.admittedRange?.start.year, 2025);
    expect(q.admittedRange?.end.year, 2025);
  });

  test('CaseQuery.fromParams falls back to defaults for empty params', () {
    expect(CaseQuery.fromParams(const {}), const CaseQuery());
  });
}
