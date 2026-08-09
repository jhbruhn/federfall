import 'package:federfall_data/federfall_data.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:test/test.dart';

class _MockPb extends Mock implements PocketBase {}

class _MockService extends Mock implements RecordService {}

void main() {
  setUpAll(() {
    registerFallbackValue(<http.MultipartFile>[]);
  });

  late _MockPb pb;
  late _MockService service;

  setUp(() {
    pb = _MockPb();
    service = _MockService();
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
        fields: any(named: 'fields'),
      ),
    ).thenAnswer((_) async => ResultList(totalItems: 3));
  });

  group('PbMicroscopySamplesRepository', () {
    late PbMicroscopySamplesRepository repo;
    setUp(() {
      when(() => pb.collection('microscopy_samples')).thenReturn(service);
      repo = PbMicroscopySamplesRepository(pb);
    });

    test('forCase() filters by case, newest sample first', () async {
      await repo.forCase('case1');
      verify(() => pb.filter('case = {:c}', {'c': 'case1'})).called(1);
      final sort = verify(
        () => service.getList(
          page: any(named: 'page'),
          perPage: any(named: 'perPage'),
          skipTotal: any(named: 'skipTotal'),
          filter: any(named: 'filter'),
          sort: captureAny(named: 'sort'),
          expand: any(named: 'expand'),
          fields: any(named: 'fields'),
        ),
      ).captured.single;
      expect(sort, '-examined_at');
    });

    group('saveWithFindings()', () {
      test('posts to the atomic microscopy route and returns the id', () async {
        when(
          () => pb.send<Map<String, dynamic>>(
            any(),
            method: any(named: 'method'),
            body: any(named: 'body'),
            files: any(named: 'files'),
          ),
        ).thenAnswer((_) async => {'id': 'm1'});

        final payload = {
          'case': 'c1',
          'sample': {'sample_type': 'fecal'},
          'findings': <Map<String, dynamic>>[],
        };
        final id = await repo.saveWithFindings(payload);

        expect(id, 'm1');
        verify(
          () => pb.send<Map<String, dynamic>>(
            '/api/federfall/microscopy',
            method: 'POST',
            body: payload,
          ),
        ).called(1);
      });

      test('passes staged attachments through as multipart files', () async {
        when(
          () => pb.send<Map<String, dynamic>>(
            any(),
            method: any(named: 'method'),
            body: any(named: 'body'),
            files: any(named: 'files'),
          ),
        ).thenAnswer((_) async => {'id': 'm1'});

        final files = [
          http.MultipartFile.fromBytes(
            'attachments',
            [1, 2, 3],
            filename: 'clip.mp4',
          ),
        ];
        await repo.saveWithFindings(
          {'id': 'm1', 'keep_attachments': <String>[]},
          attachments: files,
        );

        final sent =
            verify(
                  () => pb.send<Map<String, dynamic>>(
                    any(),
                    method: any(named: 'method'),
                    body: any(named: 'body'),
                    files: captureAny(named: 'files'),
                  ),
                ).captured.single
                as List<http.MultipartFile>;
        expect(sent.single.field, 'attachments');
      });

      test(
        'a success response without an id is an error, not an empty id',
        () async {
          when(
            () => pb.send<Map<String, dynamic>>(
              any(),
              method: any(named: 'method'),
              body: any(named: 'body'),
              files: any(named: 'files'),
            ),
          ).thenAnswer((_) async => <String, dynamic>{});

          expect(
            () => repo.saveWithFindings({'case': 'c1'}),
            throwsA(isA<RepositoryException>()),
          );
        },
      );

      test('maps ClientException to RepositoryException', () async {
        when(
          () => pb.send<Map<String, dynamic>>(
            any(),
            method: any(named: 'method'),
            body: any(named: 'body'),
            files: any(named: 'files'),
          ),
        ).thenThrow(ClientException(statusCode: 403));

        expect(
          () => repo.saveWithFindings({'id': 'm1'}),
          throwsA(isA<RepositoryException>()),
        );
      });
    });
  });

  group('PbMicroscopyFindingsRepository', () {
    late PbMicroscopyFindingsRepository repo;
    setUp(() {
      when(() => pb.collection('microscopy_findings')).thenReturn(service);
      repo = PbMicroscopyFindingsRepository(pb);
    });

    test('forSample() filters by the parent sample', () async {
      await repo.forSample('smpl1');
      verify(() => pb.filter('sample = {:s}', {'s': 'smpl1'})).called(1);
    });

    test('forCase() traverses the grandparent sample.case', () async {
      await repo.forCase('case1');
      verify(() => pb.filter('sample.case = {:c}', {'c': 'case1'})).called(1);
    });

    test('countForType() asks the server for the reference count', () async {
      expect(await repo.countForType('type1'), 3);
      verify(
        () => pb.filter('finding_type = {:t}', {'t': 'type1'}),
      ).called(1);
    });
  });

  group('PbMicroscopyFindingTypesRepository', () {
    late PbMicroscopyFindingTypesRepository repo;
    setUp(() {
      when(
        () => pb.collection('microscopy_finding_types'),
      ).thenReturn(service);
      repo = PbMicroscopyFindingTypesRepository(pb);
    });

    test('active() returns the label-sorted live vocabulary', () async {
      await repo.active();
      verify(() => pb.filter('active = true')).called(1);
      final sort = verify(
        () => service.getList(
          page: any(named: 'page'),
          perPage: any(named: 'perPage'),
          skipTotal: any(named: 'skipTotal'),
          filter: any(named: 'filter'),
          sort: captureAny(named: 'sort'),
          expand: any(named: 'expand'),
          fields: any(named: 'fields'),
        ),
      ).captured.single;
      expect(sort, 'label');
    });
  });
}
