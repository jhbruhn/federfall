import 'package:federfall_data/federfall_data.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:test/test.dart';

class _MockPb extends Mock implements PocketBase {}

void main() {
  setUpAll(() => registerFallbackValue(<String, dynamic>{}));

  late _MockPb pb;
  late PbGeocodingRepository repo;

  setUp(() {
    pb = _MockPb();
    repo = PbGeocodingRepository(pb);
  });

  test('forward maps the proxied results', () async {
    when(
      () => pb.send<Map<String, dynamic>>(any(), query: any(named: 'query')),
    ).thenAnswer(
      (_) async => {
        'results': [
          {
            'lat': 52.52,
            'lon': 13.405,
            'displayName': 'Berlin, Germany',
            'city': 'Berlin',
            'region': 'Berlin',
          },
        ],
      },
    );

    final results = await repo.forward('Berlin');

    expect(results, hasLength(1));
    expect(results.single.lat, 52.52);
    expect(results.single.lon, 13.405);
    expect(results.single.city, 'Berlin');
  });

  test('reverse maps a single result', () async {
    when(
      () => pb.send<Map<String, dynamic>>(any(), query: any(named: 'query')),
    ).thenAnswer(
      (_) async => {
        'result': {
          'lat': 52.52,
          'lon': 13.405,
          'displayName': 'Somewhere',
          'city': 'Berlin',
          'region': 'Berlin',
        },
      },
    );

    final result = await repo.reverse(52.52, 13.405);

    expect(result?.city, 'Berlin');
    expect(result?.displayName, 'Somewhere');
  });

  test('translates a ClientException into RepositoryException', () async {
    when(
      () => pb.send<Map<String, dynamic>>(any(), query: any(named: 'query')),
    ).thenThrow(ClientException(statusCode: 502));

    expect(
      () => repo.forward('boom'),
      throwsA(isA<RepositoryException>()),
    );
  });

  test(
    'forward skips malformed entries instead of fabricating (0,0) pins',
    () async {
      when(
        () => pb.send<Map<String, dynamic>>(any(), query: any(named: 'query')),
      ).thenAnswer(
        (_) async => {
          'results': [
            {'displayName': 'no coordinates at all'},
            {'lat': 'not-a-number', 'lon': 13.4, 'displayName': 'bad lat'},
            'not even a map',
            {'lat': 52.52, 'lon': 13.405, 'displayName': 'the good one'},
          ],
        },
      );

      final results = await repo.forward('Berlin');

      expect(results, hasLength(1));
      expect(results.single.displayName, 'the good one');
    },
  );

  test('reverse treats a malformed result as unresolved (null)', () async {
    when(
      () => pb.send<Map<String, dynamic>>(any(), query: any(named: 'query')),
    ).thenAnswer(
      (_) async => {
        'result': <String, dynamic>{'lat': 'x'},
      },
    );

    expect(await repo.reverse(52, 13), isNull);
  });

  test('an unexpected response shape surfaces as RepositoryException, '
      'not a raw TypeError', () async {
    when(
      () => pb.send<Map<String, dynamic>>(any(), query: any(named: 'query')),
    ).thenAnswer((_) async => {'results': 'oops, a string'});

    expect(
      () => repo.forward('boom'),
      throwsA(isA<RepositoryException>()),
    );
  });

  test('a hung request fails fast with a network error', () async {
    final slowRepo = PbGeocodingRepository(
      pb,
      networkTimeout: const Duration(milliseconds: 50),
    );
    when(
      () => pb.send<Map<String, dynamic>>(any(), query: any(named: 'query')),
    ).thenAnswer(
      (_) => Future.delayed(
        const Duration(seconds: 5),
        () => <String, dynamic>{'results': <Object?>[]},
      ),
    );

    expect(
      () => slowRepo.forward('Berlin'),
      throwsA(
        isA<RepositoryException>().having(
          (e) => e.isNetwork,
          'isNetwork',
          true,
        ),
      ),
    );
  });
}
