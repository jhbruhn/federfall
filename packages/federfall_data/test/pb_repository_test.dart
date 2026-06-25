import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:test/test.dart';

class _MockPb extends Mock implements PocketBase {}

class _MockService extends Mock implements RecordService {}

/// Minimal concrete repo over [Animal] to exercise the generic base.
class _AnimalsRepo extends PbRepository<Animal> {
  _AnimalsRepo(
    PocketBase pb, {
    super.cache,
    super.isOffline,
    super.networkTimeout = const Duration(seconds: 5),
  }) : super(pb: pb, collection: 'animals', fromRecord: Animal.fromRecord);
}

/// In-memory [RecordCache] for exercising the offline read paths.
class _MemoryCache implements RecordCache {
  final _records = <String, Map<String, dynamic>>{};
  final _lists = <String, List<Map<String, dynamic>>>{};

  @override
  Future<void> putRecord(String c, String id, Map<String, dynamic> r) async =>
      _records['$c/$id'] = r;

  @override
  Future<Map<String, dynamic>?> getRecord(String c, String id) async =>
      _records['$c/$id'];

  @override
  Future<void> putList(
    String c,
    String k,
    List<Map<String, dynamic>> r,
  ) async => _lists['$c/$k'] = r;

  @override
  Future<List<Map<String, dynamic>>?> getList(String c, String k) async =>
      _lists['$c/$k'];

  @override
  Future<void> evictRecord(String c, String id) async =>
      _records.remove('$c/$id');

  @override
  Future<void> evictLists(String c) async =>
      _lists.removeWhere((key, _) => key.startsWith('$c/'));

  @override
  Future<void> clear() async {
    _records.clear();
    _lists.clear();
  }
}

void main() {
  late _MockPb pb;
  late _MockService service;
  late _AnimalsRepo repo;

  setUp(() {
    pb = _MockPb();
    service = _MockService();
    when(() => pb.collection('animals')).thenReturn(service);
    repo = _AnimalsRepo(pb);
  });

  RecordModel rec(String id, String name) =>
      RecordModel({'id': id, 'name': name, 'species': 'Stadttaube'});

  test('list maps every record through fromRecord', () async {
    when(
      () => service.getFullList(
        filter: any(named: 'filter'),
        sort: any(named: 'sort'),
        expand: any(named: 'expand'),
      ),
    ).thenAnswer((_) async => [rec('a1', 'Lotte'), rec('a2', 'Max')]);

    final animals = await repo.list(sort: 'name');

    expect(animals.map((a) => a.name), ['Lotte', 'Max']);
  });

  test('getOne maps the record', () async {
    when(
      () => service.getOne('a1', expand: any(named: 'expand')),
    ).thenAnswer((_) async => rec('a1', 'Lotte'));

    final a = await repo.getOne('a1');

    expect(a.id, 'a1');
    expect(a.name, 'Lotte');
  });

  test('create returns the mapped created record', () async {
    when(
      () => service.create(body: any(named: 'body')),
    ).thenAnswer((_) async => rec('a3', 'Pip'));

    final a = await repo.create({'name': 'Pip', 'species': 'Stadttaube'});

    expect(a.id, 'a3');
  });

  test('createWithFiles forwards the multipart files to the service', () async {
    when(
      () => service.create(
        body: any(named: 'body'),
        files: any(named: 'files'),
      ),
    ).thenAnswer((_) async => rec('a4', 'Snap'));

    final file = http.MultipartFile.fromBytes(
      'attachments',
      [1, 2, 3],
      filename: 'photo.jpg',
    );
    final a = await repo.createWithFiles({'name': 'Snap'}, [file]);

    expect(a.id, 'a4');
    final captured =
        verify(
              () => service.create(
                body: any(named: 'body'),
                files: captureAny(named: 'files'),
              ),
            ).captured.single
            as List<http.MultipartFile>;
    expect(captured.single.field, 'attachments');
    expect(captured.single.filename, 'photo.jpg');
  });

  test('updateWithFiles forwards body and files to the service', () async {
    when(
      () => service.update(
        any(),
        body: any(named: 'body'),
        files: any(named: 'files'),
      ),
    ).thenAnswer((_) async => rec('a5', 'Edited'));

    final file = http.MultipartFile.fromBytes(
      'attachments',
      [9, 8, 7],
      filename: 'new.jpg',
    );
    final a = await repo.updateWithFiles(
      'a5',
      {
        'attachments': ['kept.jpg'],
      },
      [file],
    );

    expect(a.id, 'a5');
    final captured =
        verify(
              () => service.update(
                'a5',
                body: any(named: 'body'),
                files: captureAny(named: 'files'),
              ),
            ).captured.single
            as List<http.MultipartFile>;
    expect(captured.single.filename, 'new.jpg');
  });

  test('fileUrl builds an /api/files URL with an optional thumb', () {
    final realRepo = _AnimalsRepo(PocketBase('http://localhost:8090'));

    expect(
      realRepo.fileUrl('r1', 'pic.jpg').toString(),
      'http://localhost:8090/api/files/animals/r1/pic.jpg',
    );
    expect(
      realRepo.fileUrl('r1', 'pic.jpg', thumb: '100x100').toString(),
      contains('thumb=100x100'),
    );
  });

  test('translates ClientException into RepositoryException', () async {
    when(
      () => service.getOne(any(), expand: any(named: 'expand')),
    ).thenThrow(ClientException(statusCode: 404));

    expect(
      () => repo.getOne('missing'),
      throwsA(
        isA<RepositoryException>().having(
          (e) => e.kind,
          'kind',
          RepositoryErrorKind.notFound,
        ),
      ),
    );
  });

  test('firstWhere returns null on 404 instead of throwing', () async {
    when(
      () => service.getFirstListItem(any(), expand: any(named: 'expand')),
    ).thenThrow(ClientException(statusCode: 404));

    expect(await repo.firstWhere('name = "nope"'), isNull);
  });

  group('offline behaviour', () {
    test(
      'known-offline serves the cached list without hitting the network',
      () async {
        final cache = _MemoryCache();
        await cache.putList('animals', '|name|', [
          {'id': 'a1', 'name': 'Lotte', 'species': 'Stadttaube'},
        ]);
        final offlineRepo = _AnimalsRepo(
          pb,
          cache: cache,
          isOffline: () => true,
        );

        final animals = await offlineRepo.list(sort: 'name');

        expect(animals.single.name, 'Lotte');
        verifyNever(
          () => service.getFullList(
            filter: any(named: 'filter'),
            sort: any(named: 'sort'),
            expand: any(named: 'expand'),
          ),
        );
      },
    );

    test('known-offline throws a network error on a cache miss', () async {
      final offlineRepo = _AnimalsRepo(
        pb,
        cache: _MemoryCache(),
        isOffline: () => true,
      );

      expect(
        () => offlineRepo.list(sort: 'name'),
        throwsA(
          isA<RepositoryException>().having(
            (e) => e.isNetwork,
            'isNetwork',
            true,
          ),
        ),
      );
    });

    test('a hung request times out and falls back to the cache', () async {
      final cache = _MemoryCache();
      await cache.putList('animals', '|name|', [
        {'id': 'a1', 'name': 'Lotte', 'species': 'Stadttaube'},
      ]);
      final timeoutRepo = _AnimalsRepo(
        pb,
        cache: cache,
        networkTimeout: const Duration(milliseconds: 50),
      );
      when(
        () => service.getFullList(
          filter: any(named: 'filter'),
          sort: any(named: 'sort'),
          expand: any(named: 'expand'),
        ),
      ).thenAnswer(
        (_) => Future.delayed(const Duration(seconds: 5), () => []),
      );

      final animals = await timeoutRepo.list(sort: 'name');

      expect(animals.single.name, 'Lotte');
    });
  });
}
