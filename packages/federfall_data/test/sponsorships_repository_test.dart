import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:test/test.dart';

class _MockPb extends Mock implements PocketBase {}

class _MockService extends Mock implements RecordService {}

void main() {
  late _MockPb pb;
  late _MockService service;
  late PbSponsorshipsRepository repo;

  /// The captured arguments of the last getList call.
  var lastCall = <Symbol, dynamic>{};

  setUp(() {
    pb = _MockPb();
    service = _MockService();
    when(() => pb.collection('sponsorships')).thenReturn(service);
    // Stand in for PocketBase's parameter binding: splice the params into the
    // expression so assertions can see what would have been sent.
    when(() => pb.filter(any(), any())).thenAnswer((i) {
      var expr = i.positionalArguments.first as String;
      final params = i.positionalArguments[1] as Map<String, dynamic>? ?? {};
      for (final param in params.entries) {
        final value = param.value;
        final rendered = value is DateTime
            ? value.toUtc().toIso8601String().replaceFirst('T', ' ')
            : '$value';
        expr = expr.replaceAll('{:${param.key}}', "'$rendered'");
      }
      return expr;
    });
    repo = PbSponsorshipsRepository(pb);
    lastCall = {};
  });

  RecordModel row(String id, String name) =>
      RecordModel({'id': id, 'sponsor_name': name, 'animal': 'a1'});

  void stub(List<RecordModel> rows) {
    when(
      () => service.getList(
        page: any(named: 'page'),
        perPage: any(named: 'perPage'),
        skipTotal: any(named: 'skipTotal'),
        filter: any(named: 'filter'),
        sort: any(named: 'sort'),
        expand: any(named: 'expand'),
        fields: any(named: 'fields'),
      ),
    ).thenAnswer((i) async {
      lastCall = i.namedArguments;
      return ResultList(page: 1, perPage: 50, totalItems: -1, items: rows);
    });
  }

  String? filterSent() => lastCall[const Symbol('filter')] as String?;
  String? sortSent() => lastCall[const Symbol('sort')] as String?;

  // The instant the active/ended split is resolved against. Pinned, because
  // „läuft bis Dezember" has to come back as RUNNING and a suite asking the wall
  // clock could not say so twice.
  final now = DateTime.utc(2026, 8, 11, 12);

  group('filterFor', () {
    test('the default facet keeps unset and future end dates', () {
      // Two halves, not a negation: an unset `ended_at` is how PocketBase stores
      // "no end", and a date still to come is a patronage that is still running.
      final f = repo.filterFor(const SponsorshipQuery(), now: now);
      expect(
        f!.expression,
        '(ended_at = "" || ended_at > \'2026-08-11 12:00:00.000Z\')',
      );
    });

    test('the ended facet is the exact complement of the active one', () {
      // Every row is in exactly one of the two: a set of clauses that could
      // overlap, or leave a gap, would make the facets disagree about a row.
      final f = repo.filterFor(
        const SponsorshipQuery(status: SponsorshipStatusFilter.ended),
        now: now,
      );
      expect(
        f!.expression,
        '(ended_at != "" && ended_at <= \'2026-08-11 12:00:00.000Z\')',
      );
    });

    test('"all" narrows nothing at all', () {
      expect(
        repo.filterFor(
          const SponsorshipQuery(status: SponsorshipStatusFilter.all),
          now: now,
        ),
        isNull,
      );
    });

    test('interval matches the wire value, not the Dart name', () {
      final f = repo.filterFor(
        const SponsorshipQuery(
          status: SponsorshipStatusFilter.all,
          interval: SponsorshipInterval.oneTime,
        ),
        now: now,
      );
      expect(f!.expression, "interval = 'one_time'");
    });

    test('search matches the sponsor and the town, and nothing else', () {
      // Deliberately not the address or the mobile: neither is a question
      // anybody asks of this screen, and widening it would put more PII into the
      // shape of a query.
      final f = repo.filterFor(
        const SponsorshipQuery(
          status: SponsorshipStatusFilter.all,
          text: '  Wolf ',
        ),
        now: now,
      );
      expect(f!.expression, "(sponsor_name ~ 'Wolf' || city ~ 'Wolf')");
    });

    test('facets combine with &&, so they narrow rather than widen', () {
      final f = repo.filterFor(
        const SponsorshipQuery(
          interval: SponsorshipInterval.monthly,
          text: 'Wolf',
        ),
        now: now,
      );
      expect(f!.expression, contains(' && '));
      expect(f.expression.startsWith('(ended_at = ""'), isTrue);
      expect(f.expression, contains("interval = 'monthly'"));
      expect(f.expression, contains('sponsor_name ~'));
    });
  });

  group('isNarrowed', () {
    test('the default view narrows nothing, so empty means "nothing yet"', () {
      expect(const SponsorshipQuery().isNarrowed, isFalse);
    });

    test('any facet or a search term narrows it', () {
      expect(
        const SponsorshipQuery(
          status: SponsorshipStatusFilter.ended,
        ).isNarrowed,
        isTrue,
      );
      expect(
        const SponsorshipQuery(
          interval: SponsorshipInterval.yearly,
        ).isNarrowed,
        isTrue,
      );
      expect(const SponsorshipQuery(text: ' x ').isNarrowed, isTrue);
      // Whitespace is not a search term.
      expect(const SponsorshipQuery(text: '   ').isNarrowed, isFalse);
    });

    test('a cleared interval is gone, not carried forward', () {
      const q = SponsorshipQuery(interval: SponsorshipInterval.monthly);
      expect(q.copyWith(clearInterval: true).interval, isNull);
      expect(q.copyWith(text: 'x').interval, SponsorshipInterval.monthly);
    });
  });

  group('browse', () {
    test('pages by sponsor name, ascending', () async {
      // The screen is about PEOPLE and gets looked up by name, so the key is
      // `sponsor_name` — and it has to be the key the cursor is built from, or
      // paging returns nonsense.
      stub([row('s1', 'Abel'), row('s2', 'Wolf')]);

      final page = await repo.browse(now: now);

      expect(sortSent(), 'sponsor_name,id');
      expect(page.items.map((s) => s.sponsorName), ['Abel', 'Wolf']);
    });

    test('a page resumes AFTER the last row, never by page number', () async {
      stub(List.generate(50, (i) => row('s$i', 'Name$i')));
      final first = await repo.browse(now: now);
      expect(first.hasMore, isTrue);

      await repo.browse(after: first.cursor, now: now);

      expect(filterSent(), contains('sponsor_name >'));
      expect(lastCall[const Symbol('page')], 1);
    });

    test('the query is bound, never interpolated', () async {
      stub([]);
      await repo.browse(
        query: const SponsorshipQuery(text: "O'Brien"),
        now: now,
      );
      // The mock splices params in itself; what matters is that filterExpr was
      // asked to bind them rather than the caller building the string.
      verify(() => pb.filter(any(), any())).called(greaterThan(0));
    });
  });
}
