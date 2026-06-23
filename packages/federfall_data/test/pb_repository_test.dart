import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:test/test.dart';

class _MockPb extends Mock implements PocketBase {}

class _MockService extends Mock implements RecordService {}

/// Minimal concrete repo over [Animal] to exercise the generic base.
class _AnimalsRepo extends PbRepository<Animal> {
  _AnimalsRepo(PocketBase pb)
      : super(pb: pb, collection: 'animals', fromRecord: Animal.fromRecord);
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
    when(() => service.getOne('a1', expand: any(named: 'expand')))
        .thenAnswer((_) async => rec('a1', 'Lotte'));

    final a = await repo.getOne('a1');

    expect(a.id, 'a1');
    expect(a.name, 'Lotte');
  });

  test('create returns the mapped created record', () async {
    when(() => service.create(body: any(named: 'body')))
        .thenAnswer((_) async => rec('a3', 'Pip'));

    final a = await repo.create({'name': 'Pip', 'species': 'Stadttaube'});

    expect(a.id, 'a3');
  });

  test('translates ClientException into RepositoryException', () async {
    when(() => service.getOne(any(), expand: any(named: 'expand')))
        .thenThrow(ClientException(statusCode: 404));

    expect(
      () => repo.getOne('missing'),
      throwsA(
        isA<RepositoryException>()
            .having((e) => e.kind, 'kind', RepositoryErrorKind.notFound),
      ),
    );
  });

  test('firstWhere returns null on 404 instead of throwing', () async {
    when(
      () => service.getFirstListItem(any(), expand: any(named: 'expand')),
    ).thenThrow(ClientException(statusCode: 404));

    expect(await repo.firstWhere('name = "nope"'), isNull);
  });
}
