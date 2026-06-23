import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:test/test.dart';

class _MockPb extends Mock implements PocketBase {}

class _MockService extends Mock implements RecordService {}

/// In-memory [RecordCache] for assertions.
class _MemCache implements RecordCache {
  final records = <String, Map<String, dynamic>>{};
  final lists = <String, List<Map<String, dynamic>>>{};

  String _rk(String c, String id) => '$c/$id';

  @override
  Future<void> putRecord(String c, String id, Map<String, dynamic> r) async =>
      records[_rk(c, id)] = r;

  @override
  Future<Map<String, dynamic>?> getRecord(String c, String id) async =>
      records[_rk(c, id)];

  @override
  Future<void> putList(
    String c,
    String k,
    List<Map<String, dynamic>> r,
  ) async =>
      lists['$c/$k'] = r;

  @override
  Future<List<Map<String, dynamic>>?> getList(String c, String k) async =>
      lists['$c/$k'];

  @override
  Future<void> evictRecord(String c, String id) async =>
      records.remove(_rk(c, id));

  @override
  Future<void> evictLists(String c) async =>
      lists.removeWhere((key, _) => key.startsWith('$c/'));

  @override
  Future<void> clear() async {
    records.clear();
    lists.clear();
  }
}

class _AnimalsRepo extends PbRepository<Animal> {
  _AnimalsRepo(PocketBase pb, {super.cache})
      : super(pb: pb, collection: 'animals', fromRecord: Animal.fromRecord);
}

void main() {
  late _MockPb pb;
  late _MockService service;
  late _MemCache cache;
  late _AnimalsRepo repo;

  setUp(() {
    pb = _MockPb();
    service = _MockService();
    cache = _MemCache();
    when(() => pb.collection('animals')).thenReturn(service);
    repo = _AnimalsRepo(pb, cache: cache);
  });

  RecordModel rec(String id, String name) =>
      RecordModel({'id': id, 'name': name, 'species': 'Stadttaube'});

  group('getOne', () {
    test('caches the record on a successful read', () async {
      when(() => service.getOne('a1', expand: any(named: 'expand')))
          .thenAnswer((_) async => rec('a1', 'Lotte'));

      await repo.getOne('a1');

      expect(await cache.getRecord('animals', 'a1'), isNotNull);
    });

    test('serves the cached record on a network error', () async {
      await cache.putRecord('animals', 'a1', rec('a1', 'Lotte').toJson());
      when(() => service.getOne('a1', expand: any(named: 'expand')))
          .thenThrow(ClientException()); // statusCode 0 → network

      final a = await repo.getOne('a1');

      expect(a.name, 'Lotte', reason: 'returned from cache while offline');
    });

    test('rethrows network error when nothing is cached', () async {
      when(() => service.getOne('x', expand: any(named: 'expand')))
          .thenThrow(ClientException());

      expect(
        () => repo.getOne('x'),
        throwsA(
          isA<RepositoryException>()
              .having((e) => e.isNetwork, 'isNetwork', isTrue),
        ),
      );
    });

    test('does NOT serve cache on a non-network error (e.g. 404)', () async {
      await cache.putRecord('animals', 'a1', rec('a1', 'Lotte').toJson());
      when(() => service.getOne('a1', expand: any(named: 'expand')))
          .thenThrow(ClientException(statusCode: 404));

      expect(() => repo.getOne('a1'), throwsA(isA<RepositoryException>()));
    });
  });

  group('list', () {
    test('caches results and serves them offline', () async {
      when(
        () => service.getFullList(
          filter: any(named: 'filter'),
          sort: any(named: 'sort'),
          expand: any(named: 'expand'),
        ),
      ).thenAnswer((_) async => [rec('a1', 'Lotte'), rec('a2', 'Max')]);

      await repo.list(sort: 'name');

      // Now go offline.
      when(
        () => service.getFullList(
          filter: any(named: 'filter'),
          sort: any(named: 'sort'),
          expand: any(named: 'expand'),
        ),
      ).thenThrow(ClientException());

      final offline = await repo.list(sort: 'name');
      expect(offline.map((a) => a.name), ['Lotte', 'Max']);
    });
  });

  group('writes', () {
    test('create caches the new record and evicts lists', () async {
      await cache.putList('animals', '||', [rec('a1', 'Lotte').toJson()]);
      when(() => service.create(body: any(named: 'body')))
          .thenAnswer((_) async => rec('a3', 'Pip'));

      await repo.create({'name': 'Pip'});

      expect(await cache.getRecord('animals', 'a3'), isNotNull);
      expect(cache.lists, isEmpty, reason: 'stale lists evicted');
    });

    test('delete evicts the record', () async {
      await cache.putRecord('animals', 'a1', rec('a1', 'Lotte').toJson());
      when(() => service.delete('a1')).thenAnswer((_) async {});

      await repo.delete('a1');

      expect(await cache.getRecord('animals', 'a1'), isNull);
    });
  });
}
