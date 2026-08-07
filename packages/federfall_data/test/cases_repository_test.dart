import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:test/test.dart';

class _MockPb extends Mock implements PocketBase {}

class _MockService extends Mock implements RecordService {}

void main() {
  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(<http.MultipartFile>[]);
  });

  late _MockPb pb;
  late _MockService service;
  late PbCasesRepository repo;

  setUp(() {
    pb = _MockPb();
    service = _MockService();
    when(() => pb.collection('cases')).thenReturn(service);
    // Echo a recognisable bound-filter string so we can assert on it.
    when(
      () => pb.filter(any(), any()),
    ).thenAnswer((i) => 'BOUND:${i.positionalArguments[0]}');
    repo = PbCasesRepository(pb);
  });

  test('active() excludes disposed cases, newest first', () async {
    when(
      () => service.getList(
        page: any(named: 'page'),
        perPage: any(named: 'perPage'),
        skipTotal: any(named: 'skipTotal'),
        filter: any(named: 'filter'),
        sort: any(named: 'sort'),
        expand: any(named: 'expand'),
      ),
    ).thenAnswer((_) async => ResultList());

    await repo.active();

    final captured = verify(
      () => service.getList(
        page: any(named: 'page'),
        perPage: any(named: 'perPage'),
        skipTotal: any(named: 'skipTotal'),
        filter: captureAny(named: 'filter'),
        sort: captureAny(named: 'sort'),
        expand: any(named: 'expand'),
      ),
    ).captured;
    expect(captured[0], contains('status != '));
    expect(captured[1], '-created');
  });

  test('forAnimal() filters by the animal relation', () async {
    when(
      () => service.getList(
        page: any(named: 'page'),
        perPage: any(named: 'perPage'),
        skipTotal: any(named: 'skipTotal'),
        filter: any(named: 'filter'),
        sort: any(named: 'sort'),
        expand: any(named: 'expand'),
      ),
    ).thenAnswer((_) async => ResultList());

    await repo.forAnimal('anml1');

    verify(() => pb.filter('animal = {:a}', {'a': 'anml1'})).called(1);
  });

  group('byAnimals()', () {
    setUp(() {
      when(
        () => service.getList(
          page: any(named: 'page'),
          perPage: any(named: 'perPage'),
          skipTotal: any(named: 'skipTotal'),
          filter: any(named: 'filter'),
          sort: any(named: 'sort'),
          expand: any(named: 'expand'),
        ),
      ).thenAnswer((_) async => ResultList());
    });

    test('short-circuits to an empty list without querying', () async {
      final result = await repo.byAnimals(const []);
      expect(result, isEmpty);
      verifyNever(
        () => service.getList(
          page: any(named: 'page'),
          perPage: any(named: 'perPage'),
          skipTotal: any(named: 'skipTotal'),
          filter: any(named: 'filter'),
          sort: any(named: 'sort'),
          expand: any(named: 'expand'),
        ),
      );
    });

    test('builds an OR filter with one bound param per animal', () async {
      await repo.byAnimals(const ['a', 'b', 'c']);
      verify(
        () => pb.filter(
          'animal = {:a0} || animal = {:a1} || animal = {:a2}',
          {'a0': 'a', 'a1': 'b', 'a2': 'c'},
        ),
      ).called(1);
    });

    test('chunks a large animal set into several bounded queries', () async {
      await repo.byAnimals([for (var i = 0; i < 150; i++) 'animal$i']);
      final filters = verify(() => pb.filter(captureAny(), any())).captured;
      expect(filters, hasLength(2));
      expect('animal = '.allMatches(filters[0]! as String), hasLength(100));
      expect('animal = '.allMatches(filters[1]! as String), hasLength(50));
    });

    test('fetches duplicate animal ids only once', () async {
      await repo.byAnimals(const ['a', 'b', 'a']);
      verify(
        () => pb.filter(
          'animal = {:a0} || animal = {:a1}',
          {'a0': 'a', 'a1': 'b'},
        ),
      ).called(1);
    });
  });

  test(
    'forCarer() filters by the active_carer relation, newest first',
    () async {
      when(
        () => service.getList(
          page: any(named: 'page'),
          perPage: any(named: 'perPage'),
          skipTotal: any(named: 'skipTotal'),
          filter: any(named: 'filter'),
          sort: any(named: 'sort'),
          expand: any(named: 'expand'),
        ),
      ).thenAnswer((_) async => ResultList());

      await repo.forCarer('user1');

      verify(() => pb.filter('active_carer = {:c}', {'c': 'user1'})).called(1);
    },
  );

  group('server-side counts (federfall-s0wk)', () {
    /// Stubs the count-shaped `getList` (no sort, no expand, `fields: id`) and
    /// answers with [totalItems].
    void stubCount(int totalItems) {
      when(
        () => service.getList(
          page: any(named: 'page'),
          perPage: any(named: 'perPage'),
          skipTotal: any(named: 'skipTotal'),
          filter: any(named: 'filter'),
          fields: any(named: 'fields'),
        ),
      ).thenAnswer(
        (_) async => ResultList<RecordModel>(totalItems: totalItems),
      );
    }

    test('countWithStatus binds the WIRE value, not the Dart name', () async {
      stubCount(9);

      expect(await repo.countWithStatus(CaseStatus.readyForRelease), 9);
      // `readyForRelease` must reach PocketBase as `ready_for_release` — the
      // whole point of the enum carrying a `wire` value.
      verify(
        () => pb.filter('status = {:s}', {'s': 'ready_for_release'}),
      ).called(1);
    });

    test('countAdmittedBetween builds a half-open range in UTC', () async {
      stubCount(3);
      // Local midnights, as the dashboard builds them.
      final from = DateTime(2026);
      final to = DateTime(2027);

      expect(await repo.countAdmittedBetween(from, to), 3);

      final bound =
          verify(
                () => pb.filter(
                  'admitted_at >= {:from} && admitted_at < {:to}',
                  captureAny(),
                ),
              ).captured.single
              as Map<String, dynamic>;
      // Half-open: `>= from` and `< to`, so 31 Dec 23:59:59.999 is inside the
      // year and 1 Jan of the next is not, with nothing to round.
      final boundFrom = bound['from'] as DateTime;
      final boundTo = bound['to'] as DateTime;
      expect(boundFrom.isUtc, isTrue, reason: 'sent as an absolute instant');
      expect(boundTo.isUtc, isTrue);
      // Converted, not reinterpreted: the instant is still the caller's local
      // New Year, which off UTC is NOT midnight UTC.
      expect(boundFrom, from.toUtc());
      expect(boundTo, to.toUtc());
    });

    test('admittedBetween is INCLUSIVE at both ends', () async {
      // Unlike countAdmittedBetween's half-open year: this mirrors a range the
      // user picked, and the intake map filters again on the device with the
      // same bounds — a mismatch would put a case sitting exactly on the
      // boundary in one answer and not the other (federfall-trep).
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
      ).thenAnswer((_) async => ResultList());

      await repo.admittedBetween(DateTime(2026), DateTime(2026, 12, 31));

      verify(
        () => pb.filter(
          'admitted_at >= {:from} && admitted_at <= {:to}',
          any(),
        ),
      ).called(1);
    });

    test('a count transfers no records', () async {
      stubCount(42);

      await repo.countWithStatus(CaseStatus.disposed);

      final call = verify(
        () => service.getList(
          page: 1,
          perPage: captureAny(named: 'perPage'),
          skipTotal: captureAny(named: 'skipTotal'),
          filter: any(named: 'filter'),
          fields: captureAny(named: 'fields'),
        ),
      ).captured;
      // One row, ids only, and skipTotal false or totalItems comes back 0.
      expect(call, [1, false, 'id']);
    });
  });

  group('intake()', () {
    void stubSend(Map<String, dynamic> response) {
      when(
        () => pb.send<Map<String, dynamic>>(
          any(),
          method: any(named: 'method'),
          body: any(named: 'body'),
          files: any(named: 'files'),
        ),
      ).thenAnswer((_) async => response);
    }

    test(
      'posts payload and photos to the atomic route, returns the ids',
      () async {
        stubSend({'id': 'case1', 'animal': 'anml1'});
        final photo = http.MultipartFile.fromBytes(
          'intake_photos',
          [1, 2, 3],
          filename: 'pigeon.jpg',
        );

        final result = await repo.intake(
          {
            'case': {'admission_reason': 'injured'},
          },
          photos: [photo],
        );

        expect(result.caseId, 'case1');
        expect(result.animalId, 'anml1');
        final captured = verify(
          () => pb.send<Map<String, dynamic>>(
            captureAny(),
            method: captureAny(named: 'method'),
            body: captureAny(named: 'body'),
            files: captureAny(named: 'files'),
          ),
        ).captured;
        expect(captured[0], '/api/federfall/intake');
        expect(captured[1], 'POST');
        expect(
          (captured[2] as Map<String, dynamic>)['case'],
          {'admission_reason': 'injured'},
        );
        final files = captured[3] as List<http.MultipartFile>;
        expect(files.single.field, 'intake_photos');
        expect(files.single.filename, 'pigeon.jpg');
      },
    );

    test(
      'the idempotency key rides in the body; none sent when absent',
      () async {
        stubSend({'id': 'case1', 'animal': 'anml1'});

        await repo.intake({'species': 'Stadttaube'}, idempotencyKey: 'k1');
        await repo.intake({'species': 'Stadttaube'});

        final bodies = verify(
          () => pb.send<Map<String, dynamic>>(
            any(),
            method: any(named: 'method'),
            body: captureAny(named: 'body'),
            files: any(named: 'files'),
          ),
        ).captured.cast<Map<String, dynamic>>();
        expect(bodies.first['idempotency_key'], 'k1');
        expect(bodies.last.containsKey('idempotency_key'), isFalse);
      },
    );

    test('a keyed timeout is a plain network error — resubmitting the same '
        'key cannot duplicate the intake', () async {
      final slowRepo = PbCasesRepository(
        pb,
        networkTimeout: const Duration(milliseconds: 50),
      );
      when(
        () => pb.send<Map<String, dynamic>>(
          any(),
          method: any(named: 'method'),
          body: any(named: 'body'),
          files: any(named: 'files'),
        ),
      ).thenAnswer(
        (_) => Future.delayed(
          const Duration(seconds: 5),
          () => {'id': 'late', 'animal': 'late'},
        ),
      );

      expect(
        () => slowRepo.intake({}, idempotencyKey: 'k1'),
        throwsA(
          isA<RepositoryException>().having(
            (e) => e.kind,
            'kind',
            RepositoryErrorKind.network,
          ),
        ),
      );
    });

    test('newIdempotencyKey() yields unique 32-char hex keys', () {
      final a = newIdempotencyKey();
      final b = newIdempotencyKey();
      expect(a, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(a, isNot(b));
    });

    test('a success response missing the ids throws instead of returning '
        'empty-string ids', () async {
      stubSend({'ok': true});

      expect(
        () => repo.intake({}),
        throwsA(
          isA<RepositoryException>().having(
            (e) => e.kind,
            'kind',
            RepositoryErrorKind.unknownOutcome,
          ),
        ),
      );
    });

    test('empty-string ids in the response are rejected too', () async {
      stubSend({'id': '', 'animal': ''});

      expect(
        () => repo.intake({}),
        throwsA(isA<RepositoryException>()),
      );
    });

    test('a timeout surfaces as unknownOutcome, not network — the server '
        'may still have committed the intake', () async {
      final slowRepo = PbCasesRepository(
        pb,
        networkTimeout: const Duration(milliseconds: 50),
      );
      when(
        () => pb.send<Map<String, dynamic>>(
          any(),
          method: any(named: 'method'),
          body: any(named: 'body'),
          files: any(named: 'files'),
        ),
      ).thenAnswer(
        (_) => Future.delayed(
          const Duration(seconds: 5),
          () => {'id': 'late', 'animal': 'late'},
        ),
      );

      expect(
        () => slowRepo.intake({}),
        throwsA(
          isA<RepositoryException>()
              .having(
                (e) => e.kind,
                'kind',
                RepositoryErrorKind.unknownOutcome,
              )
              .having((e) => e.isNetwork, 'isNetwork', false),
        ),
      );
    });

    test('translates a ClientException into RepositoryException', () async {
      when(
        () => pb.send<Map<String, dynamic>>(
          any(),
          method: any(named: 'method'),
          body: any(named: 'body'),
          files: any(named: 'files'),
        ),
      ).thenThrow(ClientException(statusCode: 400));

      expect(
        () => repo.intake({}),
        throwsA(
          isA<RepositoryException>().having(
            (e) => e.kind,
            'kind',
            RepositoryErrorKind.validation,
          ),
        ),
      );
    });
  });

  group('CaseBrowseQuery → filter', () {
    setUp(() {
      // Stand in for PocketBase's parameter binding: splice the params into
      // the expression so assertions see what would have been sent.
      when(() => pb.filter(any(), any())).thenAnswer((i) {
        var expr = i.positionalArguments.first as String;
        final params = i.positionalArguments[1] as Map<String, dynamic>? ?? {};
        for (final param in params.entries) {
          expr = expr.replaceAll('{:${param.key}}', "'${param.value}'");
        }
        return expr;
      });
    });

    test('an empty query filters nothing', () {
      expect(repo.filterFor(const CaseBrowseQuery()), isNull);
    });

    test('the active split is an explicit status set, never a !=', () {
      final f = repo.filterFor(
        const CaseBrowseQuery(
          statuses: [CaseStatus.inCare, CaseStatus.readyForRelease],
          allowUnsetStatus: true,
        ),
      );

      // Spelled out rather than as a `!=` complement — a preference now, not a
      // precaution: federfall-jt5u suspected that filter shape and a live probe
      // cleared it.
      expect(
        f!.expression,
        "(status = 'in_care' || status = 'ready_for_release' "
        "|| status = '')",
      );
    });

    test('an empty carer adds no clause', () {
      // The app hands one over only while the signed-in user is still
      // unknown; `active_carer = ''` would ask for the UNASSIGNED cases.
      expect(repo.filterFor(const CaseBrowseQuery(activeCarer: '')), isNull);
      expect(
        repo
            .filterFor(
              const CaseBrowseQuery(activeCarer: '', species: 'Hohltaube'),
            )!
            .expression,
        isNot(contains('active_carer')),
      );
    });

    test('an unset status is admitted only when asked for', () {
      final f = repo.filterFor(
        const CaseBrowseQuery(statuses: [CaseStatus.disposed]),
      );

      expect(f!.expression, "(status = 'disposed')");
    });

    test('narrows by carer, species, outcome and diagnosis', () {
      final f = repo.filterFor(
        const CaseBrowseQuery(
          activeCarer: 'user1',
          species: 'Hohltaube',
          outcome: DispositionType.released,
          conditionLabel: 'Katzenbiss',
        ),
      );

      expect(f!.expression, contains("active_carer = 'user1'"));
      // Forward relation traversal onto the case's animal.
      expect(f.expression, contains("animal.species = 'Hohltaube'"));
      // A back-relation, so the any-of operator, and the WIRE value rather
      // than the Dart name.
      expect(
        f.expression,
        contains(
          "dispositions_via_case.type ?= '${DispositionType.released.wire}'",
        ),
      );
      // Both halves of what a diagnosis can be — code list or free text.
      expect(
        f.expression,
        contains("case_conditions_via_case.condition.label ?= 'Katzenbiss'"),
      );
      expect(
        f.expression,
        contains("case_conditions_via_case.free_text ?= 'Katzenbiss'"),
      );
    });

    test('text searches the case number, the animal and its markings', () {
      final f = repo.filterFor(const CaseBrowseQuery(text: 'AB12'));

      expect(f!.expression, contains("case_number ~ 'AB12'"));
      expect(f.expression, contains("animal.name ~ 'AB12'"));
      expect(
        f.expression,
        contains("animal.markings_via_animal.code ~ 'AB12'"),
      );
      // One parenthesised OR group, so a second facet cannot be swallowed.
      expect(f.expression, startsWith('('));
    });

    test('blank text narrows nothing', () {
      expect(repo.filterFor(const CaseBrowseQuery(text: '   ')), isNull);
    });

    test('the admission range is half-open and in UTC', () {
      final f = repo.filterFor(
        CaseBrowseQuery(
          admittedFrom: DateTime.utc(2026),
          admittedTo: DateTime.utc(2027),
        ),
      );

      expect(f!.expression, contains('admitted_at >='));
      expect(f.expression, contains('admitted_at <'));
      expect(f.expression, isNot(contains('admitted_at <=')));
      expect(f.expression, contains('2026-01-01'));
      expect(f.expression, contains('2027-01-01'));
    });

    test('facets are ANDed together', () {
      final f = repo.filterFor(
        const CaseBrowseQuery(activeCarer: 'user1', species: 'Hohltaube'),
      );

      expect(
        f!.expression,
        "active_carer = 'user1' && animal.species = "
        "'Hohltaube'",
      );
    });
  });

  group('browse()', () {
    ResultList<RecordModel> resultOf(List<RecordModel> items) =>
        ResultList(items: items);

    RecordModel row(String id, String created) =>
        RecordModel({'id': id, 'created': created});

    test('pages newest first and hands back a resumable cursor', () async {
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
      ).thenAnswer(
        (_) async => resultOf([
          row('case1', '2026-08-04 10:00:02.000Z'),
          row('case2', '2026-08-04 10:00:01.000Z'),
        ]),
      );

      final page = await repo.browse(perPage: 2);

      expect(page.items.map((c) => c.id), ['case1', 'case2']);
      // A full page might still be the last one, so the cursor is offered and
      // the next (empty) call settles it.
      expect(
        page.cursor,
        const PbCursor(value: '2026-08-04 10:00:01.000Z', id: 'case2'),
      );

      final captured = verify(
        () => service.getList(
          page: any(named: 'page'),
          perPage: any(named: 'perPage'),
          skipTotal: any(named: 'skipTotal'),
          filter: any(named: 'filter'),
          sort: captureAny(named: 'sort'),
          expand: any(named: 'expand'),
          fields: any(named: 'fields'),
        ),
      ).captured;
      expect(captured.single, '-created,-id');
    });

    test('a short page ends the feed', () async {
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
      ).thenAnswer(
        (_) async => resultOf([row('case1', '2026-08-04 10:00:02.000Z')]),
      );

      final page = await repo.browse();

      expect(page.hasMore, isFalse);
      expect(page.cursor, isNull);
    });
  });
}
