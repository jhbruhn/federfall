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
}
