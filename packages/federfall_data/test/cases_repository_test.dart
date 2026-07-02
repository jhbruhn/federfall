import 'package:federfall_data/federfall_data.dart';
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

    test('posts payload and photos to the atomic route, returns the ids',
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
}
