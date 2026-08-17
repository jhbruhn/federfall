import 'package:federfall_data/federfall_data.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:test/test.dart';

class _MockPb extends Mock implements PocketBase {}

class _MockService extends Mock implements RecordService {}

void main() {
  late _MockPb pb;
  late _MockService service;

  /// Stubs `pb.collection(name)` → [service] and echoes a recognisable
  /// bound-filter string so the bound expression can be asserted on.
  void wire(String collection) {
    when(() => pb.collection(collection)).thenReturn(service);
    when(
      () => pb.filter(any(), any()),
    ).thenAnswer((i) => 'BOUND:${i.positionalArguments[0]}');
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
  }

  setUp(() {
    pb = _MockPb();
    service = _MockService();
  });

  /// Captures the (filter, sort, expand) actually passed to getList.
  List<Object?> capturedQuery() => verify(
    () => service.getList(
      page: any(named: 'page'),
      perPage: any(named: 'perPage'),
      skipTotal: any(named: 'skipTotal'),
      filter: captureAny(named: 'filter'),
      sort: captureAny(named: 'sort'),
      expand: captureAny(named: 'expand'),
    ),
  ).captured;

  group('PbAnimalsRepository', () {
    setUp(() => wire('animals'));

    test('searchByName binds the query and sorts by name', () async {
      await PbAnimalsRepository(pb).searchByName('lot');
      verify(() => pb.filter('name ~ {:q}', {'q': 'lot'})).called(1);
      expect(capturedQuery()[1], 'name');
    });

    test('countHoused counts residents server-side', () async {
      // federfall-s0wk: the dashboard's "in aviary" tile. A count, so the
      // stub is the count-shaped getList (`fields: id`, `skipTotal: false`) —
      // the whole collection must not come over the wire to be filtered here.
      // The predicate is `current_aviary`, not the `lifetime_status` label:
      // since federfall-8f1m a resident under treatment reads `in_care` while
      // still occupying its enclosure, and this tile taps through to the
      // aviary registry, whose occupancy badges count exactly this.
      when(
        () => service.getList(
          page: any(named: 'page'),
          perPage: any(named: 'perPage'),
          skipTotal: any(named: 'skipTotal'),
          filter: any(named: 'filter'),
          fields: any(named: 'fields'),
        ),
      ).thenAnswer((_) async => ResultList<RecordModel>(totalItems: 5));

      final count = await PbAnimalsRepository(pb).countHoused();

      expect(count, 5);
      verify(() => pb.filter('current_aviary != ""', {})).called(1);
    });

    test('housed asks for only the two columns it tallies', () async {
      // federfall-obia: the aviary registry's occupancy badges. Its one caller
      // reads `currentAviary` and nothing else, so every housed bird's name,
      // species, notes, photo filenames and geo used to cross the wire to be
      // counted — the same over-fetch countHoused avoids on the same predicate.
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
      ).thenAnswer((_) async => ResultList<RecordModel>());

      await PbAnimalsRepository(pb).housed();

      verify(() => pb.filter('current_aviary != ""', {})).called(1);
      final fields = verify(
        () => service.getList(
          page: any(named: 'page'),
          perPage: any(named: 'perPage'),
          skipTotal: any(named: 'skipTotal'),
          filter: any(named: 'filter'),
          sort: any(named: 'sort'),
          expand: any(named: 'expand'),
          fields: captureAny(named: 'fields'),
        ),
      ).captured.single;
      // `id` travels too: fromRecord reads it, and a projection that drops it
      // hands back records that cannot be told apart.
      expect(fields, 'id,current_aviary');
    });

    test('residentsOf filters by current_aviary', () async {
      await PbAnimalsRepository(pb).residentsOf('avir1');
      verify(
        () => pb.filter('current_aviary = {:a}', {'a': 'avir1'}),
      ).called(1);
    });

    test('byIds short-circuits to an empty list without querying', () async {
      final result = await PbAnimalsRepository(pb).byIds(const []);
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

    test('byIds builds an OR filter with one bound param per id', () async {
      await PbAnimalsRepository(pb).byIds(const ['a', 'b', 'c']);
      verify(
        () => pb.filter(
          'id = {:id0} || id = {:id1} || id = {:id2}',
          {'id0': 'a', 'id1': 'b', 'id2': 'c'},
        ),
      ).called(1);
    });

    test('byIds chunks a large id set into several bounded queries', () async {
      // 250 ids -> 100 + 100 + 50, so no single GET query string can outgrow
      // URL/proxy limits (federfall-un92).
      await PbAnimalsRepository(pb).byIds([
        for (var i = 0; i < 250; i++) 'animal$i',
      ]);
      final filters = verify(() => pb.filter(captureAny(), any())).captured;
      expect(filters, hasLength(3));
      expect('id = '.allMatches(filters[0]! as String), hasLength(100));
      expect('id = '.allMatches(filters[1]! as String), hasLength(100));
      expect('id = '.allMatches(filters[2]! as String), hasLength(50));
    });

    test('byIds fetches duplicate ids only once', () async {
      await PbAnimalsRepository(pb).byIds(const ['a', 'b', 'a']);
      verify(
        () => pb.filter(
          'id = {:id0} || id = {:id1}',
          {'id0': 'a', 'id1': 'b'},
        ),
      ).called(1);
    });
  });

  group('PbAviariesRepository', () {
    setUp(() => wire('aviaries'));

    test('active filters active=true, name-sorted', () async {
      await PbAviariesRepository(pb).active();
      verify(() => pb.filter('active = true')).called(1);
      expect(capturedQuery()[1], 'name');
    });
  });

  group('PbAviaryStaysRepository', () {
    setUp(() => wire('aviary_stays'));

    test('forAviary filters by aviary, newest stay first', () async {
      await PbAviaryStaysRepository(pb).forAviary('avir1');
      verify(() => pb.filter('aviary = {:a}', {'a': 'avir1'})).called(1);
      expect(capturedQuery()[1], '-started_at');
    });

    test('forAnimal reads one bird whole history, newest first', () async {
      await PbAviaryStaysRepository(pb).forAnimal('anml1');
      verify(() => pb.filter('animal = {:a}', {'a': 'anml1'})).called(1);
      expect(capturedQuery()[1], '-started_at');
    });

    test(
      'forAnimalAt bounds the date and treats an unset end as open',
      () async {
        await PbAviaryStaysRepository(
          pb,
        ).forAnimalAt('anml1', DateTime.utc(2026, 6, 2, 7));
        verify(
          () => pb.filter(
            'animal = {:a} && started_at <= {:t}'
            " && (ended_at = '' || ended_at >= {:t})",
            {'a': 'anml1', 't': '2026-06-02T07:00:00.000Z'},
          ),
        ).called(1);
      },
    );

    test('residentsAt rosters one aviary on one date', () async {
      await PbAviaryStaysRepository(
        pb,
      ).residentsAt('avir1', DateTime.utc(2026, 6, 2, 7));
      verify(
        () => pb.filter(
          'aviary = {:v} && started_at <= {:t}'
          " && (ended_at = '' || ended_at >= {:t})",
          {'v': 'avir1', 't': '2026-06-02T07:00:00.000Z'},
        ),
      ).called(1);
      expect(capturedQuery()[1], 'started_at');
    });
  });

  group('PbCaseSharesRepository', () {
    setUp(() => wire('case_shares'));

    test('forCase filters by case and expands shared_with', () async {
      await PbCaseSharesRepository(pb).forCase('case1');
      verify(() => pb.filter('case = {:c}', {'c': 'case1'})).called(1);
      expect(capturedQuery()[2], 'shared_with');
    });

    // The share branch of custody (1700000077): user-wide and edit-only, so
    // the read shares that grant no custody never reach the predicate.
    test('editSharedWith asks user-wide, for edit access only', () async {
      await PbCaseSharesRepository(pb).editSharedWith('u1');
      verify(
        () => pb.filter('shared_with = {:u} && access = {:a}', {
          'u': 'u1',
          'a': 'edit',
        }),
      ).called(1);
    });
  });

  group('PbCaseSummariesRepository', () {
    setUp(() => wire('case_summaries'));

    test('forAnimal filters by animal, newest first', () async {
      await PbCaseSummariesRepository(pb).forAnimal('anml1');
      verify(() => pb.filter('animal = {:a}', {'a': 'anml1'})).called(1);
      expect(capturedQuery()[1], '-created');
    });
  });

  group('PbCaseLastActivityRepository', () {
    setUp(() => wire('case_activity'));

    test('all sorts by last_activity descending', () async {
      await PbCaseLastActivityRepository(pb).all();
      expect(capturedQuery()[1], '-last_activity');
    });
  });

  group('PbDispositionsRepository', () {
    setUp(() => wire('dispositions'));

    test('forCase filters by case, newest disposed first', () async {
      await PbDispositionsRepository(pb).forCase('case1');
      verify(() => pb.filter('case = {:c}', {'c': 'case1'})).called(1);
      expect(capturedQuery()[1], '-disposed_at');
    });

    test('byCases ORs the ids into one request', () async {
      // The case browser's terminal-outcome pass: one query for the page, not
      // one per case (federfall-trep).
      await PbDispositionsRepository(pb).byCases(['case1', 'case2']);
      verify(
        () => pb.filter('case = {:c0} || case = {:c1}', {
          'c0': 'case1',
          'c1': 'case2',
        }),
      ).called(1);
    });

    test('byCases short-circuits to an empty list without querying', () async {
      expect(await PbDispositionsRepository(pb).byCases(const []), isEmpty);
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
  });

  group('PbVetAppointmentsRepository', () {
    setUp(() => wire('vet_appointments'));

    test('forCase filters by case, soonest first', () async {
      await PbVetAppointmentsRepository(pb).forCase('case1');
      verify(() => pb.filter('case = {:c}', {'c': 'case1'})).called(1);
      expect(capturedQuery()[1], 'starts_at');
    });

    test(
      'openForCarer excludes attended and cancelled, bounded below',
      () async {
        final since = DateTime.utc(2026, 7, 4);
        await PbVetAppointmentsRepository(pb).openForCarer('u1', since: since);
        verify(
          () => pb.filter(
            'case.active_carer = {:u} && attended_at = "" && cancelled_at = ""'
            ' && starts_at >= {:since}',
            {'u': 'u1', 'since': since},
          ),
        ).called(1);
        expect(capturedQuery()[1], 'starts_at');
      },
    );
  });

  group('PbFindersRepository', () {
    setUp(() => wire('finders'));

    test('search binds the query across name/phone/email', () async {
      await PbFindersRepository(pb).search('berg');
      verify(
        () => pb.filter(
          'last_name ~ {:q} || first_name ~ {:q} || phone ~ {:q} '
          '|| email ~ {:q}',
          {'q': 'berg'},
        ),
      ).called(1);
      expect(capturedQuery()[1], 'last_name');
    });
  });

  group('PbUsersRepository', () {
    setUp(() => wire('users'));

    test('activeMembers filters active non-guests, name-sorted', () async {
      await PbUsersRepository(pb).activeMembers();
      verify(
        () => pb.filter('is_active = true && role != {:guest}', {
          'guest': 'guest',
        }),
      ).called(1);
      expect(capturedQuery()[1], 'name');
    });

    test('members sorts active first then by name', () async {
      await PbUsersRepository(pb).members();
      expect(capturedQuery()[1], '-is_active,name');
    });
  });

  group('PbMarkingsRepository', () {
    setUp(() => wire('markings'));

    test('forAnimal filters by animal, newest applied first', () async {
      await PbMarkingsRepository(pb).forAnimal('anml1');
      verify(() => pb.filter('animal = {:a}', {'a': 'anml1'})).called(1);
      expect(capturedQuery()[1], '-applied_at');
    });

    test('activeByCode matches code and active flag', () async {
      await PbMarkingsRepository(pb).activeByCode('DE-1');
      verify(
        () => pb.filter('code = {:c} && is_active = true', {'c': 'DE-1'}),
      ).called(1);
    });

    test('activeByAnimals ORs the ids under one active flag', () async {
      // The registry's row codes, for the page on screen rather than for the
      // whole org (federfall-trep). The OR group is parenthesised, or the
      // is_active guard would only bind to the first animal.
      await PbMarkingsRepository(pb).activeByAnimals(['a1', 'a2']);
      verify(
        () => pb.filter(
          'is_active = true && (animal = {:a0} || animal = {:a1})',
          {'a0': 'a1', 'a1': 'a2'},
        ),
      ).called(1);
    });

    test('activeByAnimals asks nothing for no animals', () async {
      expect(await PbMarkingsRepository(pb).activeByAnimals(const []), isEmpty);
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
  });

  group('PbConditionsRepository', () {
    setUp(() => wire('conditions'));

    test('active filters active=true, label-sorted', () async {
      await PbConditionsRepository(pb).active();
      verify(() => pb.filter('active = true')).called(1);
      expect(capturedQuery()[1], 'label');
    });
  });

  group('PbCaseConditionsRepository', () {
    setUp(() => wire('case_conditions'));

    test('forCase filters by case, newest first', () async {
      await PbCaseConditionsRepository(pb).forCase('case1');
      verify(() => pb.filter('case = {:c}', {'c': 'case1'})).called(1);
      expect(capturedQuery()[1], '-created');
    });

    test('byCases short-circuits to an empty list without querying', () async {
      final result = await PbCaseConditionsRepository(pb).byCases(const []);
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

    test('byCases builds an OR filter with one bound param per case', () async {
      await PbCaseConditionsRepository(pb).byCases(const ['c1', 'c2']);
      verify(
        () => pb.filter(
          'case = {:c0} || case = {:c1}',
          {'c0': 'c1', 'c1': 'c2'},
        ),
      ).called(1);
    });

    test(
      'byCases chunks a large case set into several bounded queries',
      () async {
        await PbCaseConditionsRepository(pb).byCases([
          for (var i = 0; i < 150; i++) 'case$i',
        ]);
        final filters = verify(() => pb.filter(captureAny(), any())).captured;
        expect(filters, hasLength(2));
        expect('case = '.allMatches(filters[0]! as String), hasLength(100));
        expect('case = '.allMatches(filters[1]! as String), hasLength(50));
      },
    );
  });

  group('PbOrganisationsRepository', () {
    test('binds to the organisations collection', () {
      when(() => pb.collection('organisations')).thenReturn(service);
      expect(PbOrganisationsRepository(pb).collection, 'organisations');
    });
  });
}
