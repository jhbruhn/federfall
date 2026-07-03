import 'package:federfall_data/federfall_data.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:test/test.dart';

class _MockPb extends Mock implements PocketBase {}

class _MockService extends Mock implements RecordService {}

void main() {
  late _MockPb pb;
  late _MockService service;

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

  List<Object?> capturedQuery() => verify(
    () => service.getList(
      page: any(named: 'page'),
      perPage: any(named: 'perPage'),
      skipTotal: any(named: 'skipTotal'),
      filter: captureAny(named: 'filter'),
      sort: captureAny(named: 'sort'),
      expand: any(named: 'expand'),
    ),
  ).captured;

  setUp(() {
    pb = _MockPb();
    service = _MockService();
  });

  group('PbWeightsRepository', () {
    setUp(() => wire('weights'));

    test('forCase filters by case, chronological', () async {
      await PbWeightsRepository(pb).forCase('case1');
      verify(() => pb.filter('case = {:c}', {'c': 'case1'})).called(1);
      expect(capturedQuery()[1], 'measured_at');
    });

    test('forAnimal filters by animal, chronological', () async {
      await PbWeightsRepository(pb).forAnimal('anml1');
      verify(() => pb.filter('animal = {:a}', {'a': 'anml1'})).called(1);
      expect(capturedQuery()[1], 'measured_at');
    });
  });

  group('PbMedicationsRepository', () {
    setUp(() => wire('medications'));

    test('forCase filters by case, most recently started first', () async {
      await PbMedicationsRepository(pb).forCase('case1');
      verify(() => pb.filter('case = {:c}', {'c': 'case1'})).called(1);
      expect(capturedQuery()[1], '-started_at');
    });
  });

  group('PbMedicationAdministrationsRepository', () {
    setUp(() => wire('medication_administrations'));

    test('forCase filters by case, most recent first', () async {
      await PbMedicationAdministrationsRepository(pb).forCase('case1');
      verify(() => pb.filter('case = {:c}', {'c': 'case1'})).called(1);
      expect(capturedQuery()[1], '-administered_at');
    });
  });

  group('PbJournalRepository', () {
    setUp(() => wire('journal_entries'));

    test('forCase filters by case, newest first', () async {
      await PbJournalRepository(pb).forCase('case1');
      verify(() => pb.filter('case = {:c}', {'c': 'case1'})).called(1);
      expect(capturedQuery()[1], '-entry_at');
    });
  });

  group('PbFollowUpsRepository', () {
    setUp(() => wire('follow_ups'));

    test('forCase filters by case, soonest due first', () async {
      await PbFollowUpsRepository(pb).forCase('case1');
      verify(() => pb.filter('case = {:c}', {'c': 'case1'})).called(1);
      expect(capturedQuery()[1], 'due_at');
    });

    test(
      'openForCarer joins on the carer and excludes done rechecks',
      () async {
        await PbFollowUpsRepository(pb).openForCarer('user1');
        verify(
          () => pb.filter(
            'case.active_carer = {:u} && done_at = ""',
            {'u': 'user1'},
          ),
        ).called(1);
        expect(capturedQuery()[1], 'due_at');
      },
    );
  });

  group('PbMedicationDueRepository', () {
    setUp(() => wire('medication_due'));

    test('mine filters the carer to rows with a next-due time', () async {
      await PbMedicationDueRepository(pb).mine('user1');
      verify(
        () => pb.filter(
          'active_carer = {:u} && next_due != ""',
          {'u': 'user1'},
        ),
      ).called(1);
      expect(capturedQuery()[1], 'next_due');
    });
  });

  group('PbPlacementsRepository', () {
    setUp(() => wire('placements'));

    test('forCase filters by case, newest move first', () async {
      await PbPlacementsRepository(pb).forCase('case1');
      verify(() => pb.filter('case = {:c}', {'c': 'case1'})).called(1);
      expect(capturedQuery()[1], '-moved_in_at');
    });
  });
}
