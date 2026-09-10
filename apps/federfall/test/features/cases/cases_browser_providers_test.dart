import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/cases_browser.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockCasesRepo extends Mock implements PbCasesRepository {}

class MockAnimalsRepo extends Mock implements PbAnimalsRepository {}

class MockDispositionsRepo extends Mock implements PbDispositionsRepository {}

class MockCaseConditionsRepo extends Mock
    implements PbCaseConditionsRepository {}

class MockCaseActivityRepo extends Mock
    implements PbCaseLastActivityRepository {}

Case _case(String id, {String animal = 'a1'}) => Case(id: id, animal: animal);

void main() {
  late MockCasesRepo cases;
  late MockAnimalsRepo animals;
  late MockDispositionsRepo dispositions;
  late MockCaseConditionsRepo conditions;
  late MockCaseActivityRepo activity;

  setUpAll(() => registerFallbackValue(const CaseBrowseQuery()));

  setUp(() {
    cases = MockCasesRepo();
    animals = MockAnimalsRepo();
    dispositions = MockDispositionsRepo();
    conditions = MockCaseConditionsRepo();
    activity = MockCaseActivityRepo();
    when(() => activity.byCases(any())).thenAnswer((_) async => const []);
    when(
      () => animals.byIds(any(), fields: any(named: 'fields')),
    ).thenAnswer((_) async => const []);
    when(
      () => conditions.byCases(
        any(),
        fields: any(named: 'fields'),
        openOnly: any(named: 'openOnly'),
      ),
    ).thenAnswer((_) async => const []);
  });

  void stubBrowse(PbPage<Case> Function() answer) {
    when(
      () => cases.browse(
        query: any(named: 'query'),
        after: any(named: 'after'),
        perPage: any(named: 'perPage'),
      ),
    ).thenAnswer((_) async => answer());
  }

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      // Riverpod 3 retries a failed provider on its own, which keeps it in the
      // loading state forever and makes an error assertion time out rather than
      // fail. What is under test is the first failure, not the retry policy.
      retry: (_, _) => null,
      overrides: [
        casesRepositoryProvider.overrideWith((ref) async => cases),
        animalsRepositoryProvider.overrideWith((ref) async => animals),
        dispositionsRepositoryProvider.overrideWith(
          (ref) async => dispositions,
        ),
        caseConditionsRepositoryProvider.overrideWith(
          (ref) async => conditions,
        ),
        caseActivityRepositoryProvider.overrideWith((ref) async => activity),
        currentUserProvider.overrideWith((ref) async => null),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('a page fetches its own diagnoses, narrowed server-side', () async {
    // federfall-trep's rule on this screen: the device receives the rows it is
    // about to draw. Unresolved only, and over the page's own case ids — never
    // the collection, and never narrowed here.
    stubBrowse(() => PbPage(items: [_case('c1'), _case('c2')]));
    when(
      () => conditions.byCases(
        any(),
        fields: any(named: 'fields'),
        openOnly: any(named: 'openOnly'),
      ),
    ).thenAnswer(
      (_) async => const [
        CaseCondition(id: 'x1', caseId: 'c1', freeText: 'Cat bite'),
        CaseCondition(id: 'x2', caseId: 'c1', freeText: 'Fracture'),
        CaseCondition(id: 'x3', caseId: 'c2', freeText: 'Lead'),
      ],
    );

    final state = await makeContainer().read(
      caseBrowseFeedProvider(const CaseQuery()).future,
    );

    // Grouped by case, and a case with none is simply absent.
    expect(state.diagnosesByCase['c1']?.map((d) => d.freeText), [
      'Cat bite',
      'Fracture',
    ]);
    expect(state.diagnosesByCase['c2']?.map((d) => d.freeText), ['Lead']);

    final asked = verify(
      () => conditions.byCases(
        captureAny(),
        fields: any(named: 'fields'),
        openOnly: captureAny(named: 'openOnly'),
      ),
    ).captured;
    expect((asked[0] as Iterable<String>).toList(), ['c1', 'c2']);
    expect(asked[1], isTrue);
  });

  group('refreshDiagnoses (federfall-78k6.5)', () {
    test(
      're-reads the subtitles without disturbing the rows or the cursor',
      () async {
        // Recording a diagnosis in the detail pane beside the list changes what
        // a row says, not which rows there are. Invalidating the feed would
        // also work and would throw away the paging and the scroll position to
        // change one line of text.
        stubBrowse(
          () => PbPage(
            items: [_case('c1'), _case('c2')],
            cursor: const PbCursor(value: '2026-08-04 10:00:00.000Z', id: 'c2'),
          ),
        );
        when(
          () => conditions.byCases(
            any(),
            fields: any(named: 'fields'),
            openOnly: any(named: 'openOnly'),
          ),
        ).thenAnswer((_) async => const []);

        final container = makeContainer();
        const query = CaseQuery();
        final before = await container.read(
          caseBrowseFeedProvider(query).future,
        );
        expect(before.diagnosesByCase, isEmpty);

        when(
          () => conditions.byCases(
            any(),
            fields: any(named: 'fields'),
            openOnly: any(named: 'openOnly'),
          ),
        ).thenAnswer(
          (_) async => const [
            CaseCondition(id: 'x1', caseId: 'c1', freeText: 'Fracture'),
          ],
        );
        await container
            .read(caseBrowseFeedProvider(query).notifier)
            .refreshDiagnoses();

        final after = container.read(caseBrowseFeedProvider(query)).value!;
        expect(after.diagnosesByCase['c1']?.single.freeText, 'Fracture');
        // Everything paging depends on is untouched.
        expect(after.cases.map((c) => c.id), ['c1', 'c2']);
        expect(after.cursor?.id, 'c2');
        expect(after.hasMore, isTrue);
      },
    );

    test('a failed re-read keeps the subtitles already on screen', () async {
      stubBrowse(() => PbPage(items: [_case('c1')]));
      when(
        () => conditions.byCases(
          any(),
          fields: any(named: 'fields'),
          openOnly: any(named: 'openOnly'),
        ),
      ).thenAnswer(
        (_) async => const [
          CaseCondition(id: 'x1', caseId: 'c1', freeText: 'Fracture'),
        ],
      );

      final container = makeContainer();
      const query = CaseQuery();
      await container.read(caseBrowseFeedProvider(query).future);

      when(
        () => conditions.byCases(
          any(),
          fields: any(named: 'fields'),
          openOnly: any(named: 'openOnly'),
        ),
      ).thenThrow(
        const RepositoryException('offline', kind: RepositoryErrorKind.network),
      );
      await container
          .read(caseBrowseFeedProvider(query).notifier)
          .refreshDiagnoses();

      // A subtitle is worth a retry on the next event, never the list.
      final after = container.read(caseBrowseFeedProvider(query)).value!;
      expect(after.diagnosesByCase['c1']?.single.freeText, 'Fracture');
      expect(after.cases, hasLength(1));
    });
  });

  test('a dropped connection surfaces as itself, not wrapped', () {
    // federfall-s5mm, end to end on the busiest screen in the app. Gathered
    // with `(a, b, …).wait` this arrived as a ParallelWaitError, which
    // `isNetworkError` does not recognise — so the case browser showed a
    // generic error and threw away the list, the scroll position and the
    // filters, instead of keeping them until the connection returned.
    stubBrowse(
      () => throw const RepositoryException(
        'Could not reach the server',
        kind: RepositoryErrorKind.network,
      ),
    );

    return expectLater(
      makeContainer().read(caseBrowseFeedProvider(const CaseQuery()).future),
      throwsA(
        isA<RepositoryException>().having(
          (e) => e.kind,
          'kind',
          RepositoryErrorKind.network,
        ),
      ),
    );
  });

  test('the first page carries its cases and their animals', () async {
    stubBrowse(
      () => PbPage(
        items: [
          _case('c1'),
          _case('c2', animal: 'a2'),
        ],
        cursor: const PbCursor(value: '2026-08-04 10:00:00.000Z', id: 'c2'),
      ),
    );
    when(() => animals.byIds(any(), fields: any(named: 'fields'))).thenAnswer(
      (_) async => const [
        Animal(id: 'a1', species: 'Columba livia'),
        Animal(id: 'a2', species: 'Streptopelia decaocto'),
      ],
    );

    final state = await makeContainer().read(
      caseBrowseFeedProvider(const CaseQuery()).future,
    );

    expect(state.cases.map((c) => c.id), ['c1', 'c2']);
    expect(state.animalsById.keys, ['a1', 'a2']);
    expect(state.hasMore, isTrue);
    // Only the two columns a row draws cross the wire.
    final fields = verify(
      () => animals.byIds(any(), fields: captureAny(named: 'fields')),
    ).captured.single;
    expect(fields, 'id,species,name,photo');
  });

  test('the resolved query reaches the repository', () async {
    stubBrowse(() => const PbPage(items: []));

    await makeContainer().read(
      caseBrowseFeedProvider(
        const CaseQuery(activity: CaseActivity.closed, species: 'Hohltaube'),
      ).future,
    );

    final query =
        verify(
              () => cases.browse(
                query: captureAny(named: 'query'),
                after: any(named: 'after'),
                perPage: any(named: 'perPage'),
              ),
            ).captured.single
            as CaseBrowseQuery;
    expect(query.statuses, [CaseStatus.disposed]);
    expect(query.species, 'Hohltaube');
  });

  test('a self-contradictory query answers empty without a request', () async {
    // `?activity=closed&status=in_care` — reachable by hand-editing a link.
    final state = await makeContainer().read(
      caseBrowseFeedProvider(
        const CaseQuery(
          activity: CaseActivity.closed,
          status: CaseStatus.inCare,
        ),
      ).future,
    );

    expect(state.cases, isEmpty);
    expect(state.hasMore, isFalse);
    verifyNever(
      () => cases.browse(
        query: any(named: 'query'),
        after: any(named: 'after'),
        perPage: any(named: 'perPage'),
      ),
    );
  });

  group('the outcome facet is narrowed to the TERMINAL disposition', () {
    setUp(() {
      // The server matches "carries a disposition of this type", so a
      // re-disposed case comes back for its earlier outcome too.
      stubBrowse(
        () => const PbPage(
          items: [Case(id: 'c1', animal: 'a1')],
        ),
      );
      when(() => dispositions.byCases(any())).thenAnswer(
        (_) async => [
          Disposition(
            id: 'd1',
            caseId: 'c1',
            type: DispositionType.placedInAviary,
            disposedAt: DateTime.utc(2026, 3),
          ),
          Disposition(
            id: 'd2',
            caseId: 'c1',
            type: DispositionType.released,
            disposedAt: DateTime.utc(2026, 5),
          ),
        ],
      );
    });

    test('the superseded outcome is dropped from the page', () async {
      final state = await makeContainer().read(
        caseBrowseFeedProvider(
          const CaseQuery(outcome: DispositionType.placedInAviary),
        ).future,
      );

      expect(state.cases, isEmpty);
    });

    test('the terminal outcome is kept', () async {
      final state = await makeContainer().read(
        caseBrowseFeedProvider(
          const CaseQuery(outcome: DispositionType.released),
        ).future,
      );

      expect(state.cases.map((c) => c.id), ['c1']);
    });

    test('no outcome facet costs no dispositions request', () async {
      await makeContainer().read(
        caseBrowseFeedProvider(const CaseQuery()).future,
      );

      verifyNever(() => dispositions.byCases(any()));
    });
  });

  group('a page refined away by the outcome facet is not the answer', () {
    // Every case here carries a superseded disposition of the type asked for,
    // so the refinement empties whole server pages (federfall-etd7).
    void stubSupersededPages({required int matchOn, required int pages}) {
      var call = 0;
      stubBrowse(() {
        final n = call++;
        return PbPage(
          items: [_case('c$n')],
          cursor: n < pages - 1 ? PbCursor(value: 'x$n', id: 'c$n') : null,
        );
      });
      when(() => dispositions.byCases(any())).thenAnswer((invocation) async {
        final id =
            (invocation.positionalArguments.first as Iterable<String>).single;
        return [
          Disposition(
            id: 'd-$id-1',
            caseId: id,
            type: DispositionType.released,
            disposedAt: DateTime.utc(2026, 3),
          ),
          Disposition(
            id: 'd-$id-2',
            caseId: id,
            // Only the page named by `matchOn` keeps a released terminal
            // outcome; the rest were re-disposed into an aviary afterwards.
            type: id == 'c$matchOn'
                ? DispositionType.released
                : DispositionType.placedInAviary,
            disposedAt: DateTime.utc(2026, 5),
          ),
        ];
      });
    }

    test('the next page is fetched until a row survives', () async {
      stubSupersededPages(matchOn: 2, pages: 4);

      final state = await makeContainer().read(
        caseBrowseFeedProvider(
          const CaseQuery(outcome: DispositionType.released),
        ).future,
      );

      // Not the empty list the first two pages alone would have produced —
      // which the screen would have shown as "no matches" for good.
      expect(state.cases.map((c) => c.id), ['c2']);
      verify(
        () => cases.browse(
          query: any(named: 'query'),
          after: any(named: 'after'),
          perPage: any(named: 'perPage'),
        ),
      ).called(3);
    });

    test('the scan is bounded, and leaves a cursor to resume from', () async {
      // Nothing ever matches: without a bound this would walk the collection.
      stubSupersededPages(matchOn: -1, pages: 1000);

      final container = makeContainer();
      final feed = caseBrowseFeedProvider(
        const CaseQuery(outcome: DispositionType.released),
      );
      final state = await container.read(feed.future);

      expect(state.cases, isEmpty);
      // Still more to read — the empty state must not claim "no matches", and
      // the next loadMore picks up where this stopped rather than at the top.
      expect(state.hasMore, isTrue);
      expect(state.cursor, isNotNull);
      verify(
        () => cases.browse(
          query: any(named: 'query'),
          after: any(named: 'after'),
          perPage: any(named: 'perPage'),
        ),
      ).called(10);

      await container.read(feed.notifier).loadMore();

      expect(container.read(feed).requireValue.cursor, isNot(state.cursor));
    });
  });

  group('loadMore', () {
    test('appends the next page and keeps the rows on screen', () async {
      var call = 0;
      stubBrowse(
        () => call++ == 0
            ? PbPage(
                items: [_case('c1')],
                cursor: const PbCursor(value: 'x', id: 'c1'),
              )
            : const PbPage(
                items: [Case(id: 'c2', animal: 'a1')],
              ),
      );
      final container = makeContainer();
      final feed = caseBrowseFeedProvider(const CaseQuery());
      await container.read(feed.future);

      await container.read(feed.notifier).loadMore();

      final state = container.read(feed).requireValue;
      expect(state.cases.map((c) => c.id), ['c1', 'c2']);
      expect(state.hasMore, isFalse);
    });

    test('a failed page keeps the list and offers a retry', () async {
      var call = 0;
      stubBrowse(() {
        switch (call++) {
          case 0:
            return PbPage(
              items: [_case('c1')],
              cursor: const PbCursor(value: 'x', id: 'c1'),
            );
          case 1:
            throw const RepositoryException('boom');
          default:
            return const PbPage(
              items: [Case(id: 'c2', animal: 'a1')],
            );
        }
      });
      final container = makeContainer();
      final feed = caseBrowseFeedProvider(const CaseQuery());
      await container.read(feed.future);

      await container.read(feed.notifier).loadMore();

      final failed = container.read(feed).requireValue;
      // federfall-ia9n: the rows already read stay, and the cursor with them,
      // so the retry resumes with no gap and no duplicates.
      expect(failed.cases.map((c) => c.id), ['c1']);
      expect(failed.pageError, isA<RepositoryException>());
      expect(failed.cursor, const PbCursor(value: 'x', id: 'c1'));

      // And it does not auto-retry against a server that is down.
      await container.read(feed.notifier).loadMore();
      expect(call, 2);

      await container.read(feed.notifier).retryPage();
      final recovered = container.read(feed).requireValue;
      expect(recovered.cases.map((c) => c.id), ['c1', 'c2']);
      expect(recovered.pageError, isNull);
    });

    test('is a no-op once the list is exhausted', () async {
      stubBrowse(() => PbPage(items: [_case('c1')]));
      final container = makeContainer();
      final feed = caseBrowseFeedProvider(const CaseQuery());
      await container.read(feed.future);

      await container.read(feed.notifier).loadMore();

      verify(
        () => cases.browse(
          query: any(named: 'query'),
          after: any(named: 'after'),
          perPage: any(named: 'perPage'),
        ),
      ).called(1);
    });
  });
}
