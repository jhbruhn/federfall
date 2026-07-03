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

  group('PbCaseSharesRepository', () {
    setUp(() => wire('case_shares'));

    test('forCase filters by case and expands shared_with', () async {
      await PbCaseSharesRepository(pb).forCase('case1');
      verify(() => pb.filter('case = {:c}', {'c': 'case1'})).called(1);
      expect(capturedQuery()[2], 'shared_with');
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
  });

  group('PbOrganisationsRepository', () {
    test('binds to the organisations collection', () {
      when(() => pb.collection('organisations')).thenReturn(service);
      expect(PbOrganisationsRepository(pb).collection, 'organisations');
    });
  });
}
