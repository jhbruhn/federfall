import 'package:federfall/features/cases/cases_browser.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_test/flutter_test.dart';

Disposition _disp(
  String id,
  String caseId,
  DispositionType? type, {
  DateTime? at,
}) => Disposition(id: id, caseId: caseId, type: type, disposedAt: at);

void main() {
  // Every facet is resolved by the server now (federfall-trep), so what these
  // assert is the translation: the same question, asked of PocketBase.
  CaseBrowseQuery browse(CaseQuery query) => query.toBrowseQuery('me');

  group('CaseQuery → CaseBrowseQuery', () {
    test("the default scope asks for the user's own active cases", () {
      final q = browse(const CaseQuery());

      expect(q.activeCarer, 'me');
      expect(q.statuses, [CaseStatus.inCare, CaseStatus.readyForRelease]);
      // `cases.status` is optional, and a case without one has always counted
      // as active — so the complement of "disposed" has to include it.
      expect(q.allowUnsetStatus, isTrue);
    });

    test('the all scope names no carer and lets the rules scope it', () {
      expect(browse(const CaseQuery(allScope: true)).activeCarer, isNull);
    });

    test('closed asks for disposed alone, and not for the unset status', () {
      final q = browse(const CaseQuery(activity: CaseActivity.closed));

      expect(q.statuses, [CaseStatus.disposed]);
      expect(q.allowUnsetStatus, isFalse);
    });

    test('the all activity narrows by no status at all', () {
      final q = browse(const CaseQuery(activity: CaseActivity.all));

      expect(q.statuses, isEmpty);
      expect(q.allowUnsetStatus, isTrue);
    });

    test('an exact status supersedes the activity split', () {
      final q = browse(
        const CaseQuery(
          activity: CaseActivity.all,
          status: CaseStatus.readyForRelease,
        ),
      );

      expect(q.statuses, [CaseStatus.readyForRelease]);
      // Naming a status must not also match a case that has none.
      expect(q.allowUnsetStatus, isFalse);
    });

    test('an exact status the activity excludes matches nothing', () {
      // Reachable by hand-editing a deep link. The two filters have always
      // intersected, so the honest answer is an empty result — and the feed
      // gives it without asking the server.
      const q = CaseQuery(
        activity: CaseActivity.closed,
        status: CaseStatus.inCare,
      );

      expect(q.matchesNothing, isTrue);
      expect(browse(q).statuses, isEmpty);
      expect(const CaseQuery().matchesNothing, isFalse);
      expect(
        const CaseQuery(status: CaseStatus.inCare).matchesNothing,
        isFalse,
      );
    });

    test('species, outcome, diagnosis and text carry straight over', () {
      final q = browse(
        const CaseQuery(
          species: 'Streptopelia decaocto',
          outcome: DispositionType.released,
          condition: 'Trichomoniasis',
          text: '042',
        ),
      );

      expect(q.species, 'Streptopelia decaocto');
      expect(q.outcome, DispositionType.released);
      expect(q.conditionLabel, 'Trichomoniasis');
      expect(q.text, '042');
    });

    test('a carer filter replaces the mine/all scope', () {
      // Intersecting the two would yield nothing for every carer but the
      // signed-in one (federfall-9mit).
      expect(browse(const CaseQuery(carer: 'other')).activeCarer, 'other');
      expect(
        browse(const CaseQuery(allScope: true, carer: 'other')).activeCarer,
        'other',
      );
    });

    test('a carer filter still leaves the other facets in force', () {
      // The workload card counts OPEN cases, so its tap-through must land on
      // the browser's active default — the same number it showed.
      final q = browse(const CaseQuery(carer: 'other'));

      expect(q.statuses, [CaseStatus.inCare, CaseStatus.readyForRelease]);
    });

    test('the date range becomes a half-open pair of local midnights', () {
      final q = browse(
        CaseQuery(
          admittedRange: DateTimeRange(
            start: DateTime(2026, 6, 2, 14, 30),
            end: DateTime(2026, 6, 30, 8),
          ),
        ),
      );

      // The picker's end is the last DAY the user means to include, so the
      // bound is the start of the next one — a case admitted at 23:30 on the
      // 30th is inside its own range.
      expect(q.admittedFrom, DateTime(2026, 6, 2));
      expect(q.admittedTo, DateTime(2026, 7));
    });

    test("the admission day is the DEVICE's, not UTC's", () {
      // federfall-s0wk: `admitted_at` is stored UTC (pbDate normalises with
      // `.toUtc()`) while the range comes from a date picker, i.e. local days.
      // Building the bounds from UTC days compared the two across zones — and
      // the dashboard's "intakes this year" tile resolves its boundary
      // locally, so the count and the list it opens disagreed on New Year's.
      final offset = DateTime.now().timeZoneOffset;
      final q = browse(
        CaseQuery(
          admittedRange: DateTimeRange(
            start: DateTime(2026),
            end: DateTime(2026, 12, 31),
          ),
        ),
      );

      // Local midnights, so the instant a bird was admitted at 00:30 on New
      // Year's Day in UTC+1 falls inside the year the carer means.
      expect(q.admittedFrom!.isUtc, isFalse);
      expect(q.admittedFrom, DateTime(2026));
      expect(q.admittedTo, DateTime(2027));
      expect(
        DateTime(2026).toUtc().year == 2025 || offset == Duration.zero,
        isTrue,
        reason: offset == Duration.zero
            ? 'device is on UTC: this test cannot distinguish the readings'
            : 'expected local New Year to fall in the previous UTC year',
      );
    });

    test('an unknown signed-in user carries no carer id', () {
      // Only reachable while signed out. The repository drops an empty carer
      // rather than asking for the unassigned cases — see its own tests.
      expect(const CaseQuery().toBrowseQuery('').activeCarer, isEmpty);
    });
  });

  group('terminalDispositionByCase', () {
    test('keeps the latest disposition when a case was re-dispositioned', () {
      final terminal = terminalDispositionByCase([
        _disp(
          'd1',
          'c1',
          DispositionType.placedInAviary,
          at: DateTime(2026, 3),
        ),
        _disp('d2', 'c1', DispositionType.released, at: DateTime(2026, 5)),
      ]);

      expect(terminal['c1']?.type, DispositionType.released);
    });

    test('is what narrows the outcome facet past the server filter', () {
      // The server can only match "carries a disposition of this type", which
      // over-matches the case above for `placedInAviary`. This is the pass
      // that keeps the browser agreeing with `case_report_rows`.
      final terminal = terminalDispositionByCase([
        _disp(
          'd1',
          'c1',
          DispositionType.placedInAviary,
          at: DateTime(2026, 3),
        ),
        _disp('d2', 'c1', DispositionType.released, at: DateTime(2026, 5)),
      ]);

      expect(
        terminal['c1']?.type == DispositionType.placedInAviary,
        isFalse,
      );
    });

    test('a disposition of an unknown type resolves to no outcome', () {
      // It can be counted in the statistics as "unknown", but there is no
      // filter value that names it, so no facet may claim to match it.
      final terminal = terminalDispositionByCase([_disp('d1', 'c1', null)]);

      expect(terminal['c1']?.type, isNull);
    });
  });

  group('CaseQuery value semantics', () {
    test('a carer facet counts instead of the scope it supersedes', () {
      expect(const CaseQuery().activeFacetCount, 0);
      expect(const CaseQuery(allScope: true).activeFacetCount, 1);
      expect(const CaseQuery(carer: 'other').activeFacetCount, 1);
      // Not 2: the scope toggle is inert while a carer is named, so badging
      // both would count a filter the user cannot see.
      expect(
        const CaseQuery(allScope: true, carer: 'other').activeFacetCount,
        1,
      );
    });

    test('isNarrowed is what tells "no cases" from "no matches"', () {
      // The loaded rows can no longer say which emptiness this is — the server
      // sends only what matched — so the empty state reads this instead.
      expect(const CaseQuery().isNarrowed, isFalse);
      expect(const CaseQuery(text: '  ').isNarrowed, isFalse);
      expect(const CaseQuery(text: 'pip').isNarrowed, isTrue);
      expect(const CaseQuery(allScope: true).isNarrowed, isTrue);
      expect(const CaseQuery(species: 'Columba livia').isNarrowed, isTrue);
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
      // The feed is a family keyed on this object, so equality is what decides
      // whether a filter change starts a new list or reuses the loaded pages.
      expect(const CaseQuery(carer: 'a'), isNot(const CaseQuery(carer: 'b')));
      expect(const CaseQuery(carer: 'a'), isNot(const CaseQuery()));
      expect(const CaseQuery(carer: 'a'), const CaseQuery(carer: 'a'));
      expect(
        const CaseQuery(carer: 'a').hashCode,
        const CaseQuery(carer: 'a').hashCode,
      );
    });

    test('CaseQuery.fromParams falls back to defaults for empty params', () {
      expect(CaseQuery.fromParams(const {}), const CaseQuery());
    });
  });
}
