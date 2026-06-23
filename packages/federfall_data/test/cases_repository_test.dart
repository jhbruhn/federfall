import 'package:federfall_data/federfall_data.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:test/test.dart';

class _MockPb extends Mock implements PocketBase {}

class _MockService extends Mock implements RecordService {}

void main() {
  late _MockPb pb;
  late _MockService service;
  late PbCasesRepository repo;

  setUp(() {
    pb = _MockPb();
    service = _MockService();
    when(() => pb.collection('cases')).thenReturn(service);
    // Echo a recognisable bound-filter string so we can assert on it.
    when(() => pb.filter(any(), any()))
        .thenAnswer((i) => 'BOUND:${i.positionalArguments[0]}');
    repo = PbCasesRepository(pb);
  });

  test('active() excludes disposed cases, newest first', () async {
    when(
      () => service.getFullList(
        filter: any(named: 'filter'),
        sort: any(named: 'sort'),
        expand: any(named: 'expand'),
      ),
    ).thenAnswer((_) async => []);

    await repo.active();

    final captured = verify(
      () => service.getFullList(
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
      () => service.getFullList(
        filter: any(named: 'filter'),
        sort: any(named: 'sort'),
        expand: any(named: 'expand'),
      ),
    ).thenAnswer((_) async => []);

    await repo.forAnimal('anml1');

    verify(() => pb.filter('animal = {:a}', {'a': 'anml1'})).called(1);
  });

  test('forCarer() filters by the active_carer relation, newest first',
      () async {
    when(
      () => service.getFullList(
        filter: any(named: 'filter'),
        sort: any(named: 'sort'),
        expand: any(named: 'expand'),
      ),
    ).thenAnswer((_) async => []);

    await repo.forCarer('user1');

    verify(() => pb.filter('active_carer = {:c}', {'c': 'user1'})).called(1);
  });
}
