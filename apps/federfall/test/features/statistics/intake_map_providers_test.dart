import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/statistics/intake_map_providers.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockCasesRepo extends Mock implements PbCasesRepository {}

class MockAnimalsRepo extends Mock implements PbAnimalsRepository {}

Case _case(
  String id, {
  String animal = 'a1',
  DateTime? admittedAt,
  GeoPoint? findGeo,
}) => Case(
  id: id,
  animal: animal,
  admittedAt: admittedAt,
  findGeo: findGeo,
);

void main() {
  const geo = GeoPoint(lat: 52.5, lon: 13.4);

  test('drops cases with no find-location', () {
    final result = filterIntakeLocations(
      cases: [
        _case('c1'),
        _case('c2', findGeo: geo),
      ],
      speciesByAnimal: const {},
    );
    expect(result.map((l) => l.caseId), ['c2']);
  });

  test('with no range, keeps cases regardless of admittedAt', () {
    final result = filterIntakeLocations(
      cases: [
        _case('c1', findGeo: geo),
        _case('c2', findGeo: geo, admittedAt: DateTime(2020)),
      ],
      speciesByAnimal: const {},
    );
    expect(result.map((l) => l.caseId), ['c1', 'c2']);
  });

  test('with a range, drops cases with no admittedAt', () {
    final result = filterIntakeLocations(
      cases: [_case('c1', findGeo: geo)],
      speciesByAnimal: const {},
      admittedRange: DateTimeRange(start: DateTime(2024), end: DateTime(2025)),
    );
    expect(result, isEmpty);
  });

  test('with a range, keeps only cases admitted inside it', () {
    final range = DateTimeRange(start: DateTime(2024), end: DateTime(2025));
    final result = filterIntakeLocations(
      cases: [
        _case('inside', findGeo: geo, admittedAt: DateTime(2024, 6)),
        _case('before', findGeo: geo, admittedAt: DateTime(2023, 6)),
        _case('after', findGeo: geo, admittedAt: DateTime(2026, 6)),
      ],
      speciesByAnimal: const {},
      admittedRange: range,
    );
    expect(result.map((l) => l.caseId), ['inside']);
  });

  test('resolves species via the animal lookup', () {
    final result = filterIntakeLocations(
      cases: [_case('c1', findGeo: geo)],
      speciesByAnimal: const {'a1': 'Pigeon'},
    );
    expect(result.single.species, 'Pigeon');
  });

  test('resolves the animal name via the name lookup, when given', () {
    final withName = filterIntakeLocations(
      cases: [_case('c1', findGeo: geo)],
      speciesByAnimal: const {},
      nameByAnimal: const {'a1': 'Pip'},
    );
    expect(withName.single.animalName, 'Pip');

    final withoutName = filterIntakeLocations(
      cases: [_case('c1', findGeo: geo)],
      speciesByAnimal: const {},
    );
    expect(withoutName.single.animalName, isNull);
  });

  test('projects lat/lon into a LatLng point', () {
    final result = filterIntakeLocations(
      cases: [_case('c1', findGeo: geo)],
      speciesByAnimal: const {},
    );
    expect(result.single.point.latitude, geo.lat);
    expect(result.single.point.longitude, geo.lon);
  });

  group('what it asks the server for (federfall-trep)', () {
    late MockCasesRepo cases;
    late MockAnimalsRepo animals;

    setUpAll(() => registerFallbackValue(DateTime(0)));

    setUp(() {
      cases = MockCasesRepo();
      animals = MockAnimalsRepo();
      when(
        () => cases.list(
          filter: any(named: 'filter'),
          sort: any(named: 'sort'),
          expand: any(named: 'expand'),
          fields: any(named: 'fields'),
        ),
      ).thenAnswer((_) async => [_case('c1', findGeo: geo)]);
      when(
        () => cases.admittedBetween(any(), any()),
      ).thenAnswer((_) async => [_case('c1', findGeo: geo)]);
      when(
        () => animals.byIds(any(), fields: any(named: 'fields')),
      ).thenAnswer((_) async => const []);
      when(
        () => animals.list(
          filter: any(named: 'filter'),
          sort: any(named: 'sort'),
          expand: any(named: 'expand'),
          fields: any(named: 'fields'),
        ),
      ).thenAnswer((_) async => const []);
    });

    ProviderContainer makeContainer() {
      final container = ProviderContainer(
        overrides: [
          casesRepositoryProvider.overrideWith((ref) async => cases),
          animalsRepositoryProvider.overrideWith((ref) async => animals),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test(
      'a period is asked of the server, not filtered on the device',
      () async {
        final range = DateTimeRange(
          start: DateTime(2026),
          end: DateTime(2026, 12, 31),
        );

        await makeContainer().read(
          intakeLocationsProvider(admittedRange: range).future,
        );

        verify(() => cases.admittedBetween(range.start, range.end)).called(1);
        verifyNever(
          () => cases.list(
            filter: any(named: 'filter'),
            sort: any(named: 'sort'),
            expand: any(named: 'expand'),
            fields: any(named: 'fields'),
          ),
        );
      },
    );

    test(
      'all time still reads every case — there is no period to ask for',
      () async {
        await makeContainer().read(intakeLocationsProvider().future);

        verifyNever(() => cases.admittedBetween(any(), any()));
        verify(
          () => cases.list(
            filter: any(named: 'filter'),
            sort: any(named: 'sort'),
            expand: any(named: 'expand'),
            fields: any(named: 'fields'),
          ),
        ).called(1);
      },
    );

    test(
      'only the animals those cases name, and only the columns used',
      () async {
        await makeContainer().read(intakeLocationsProvider().future);

        // Pulling every animal in the org to build a species lookup is the read
        // this issue removed.
        verifyNever(
          () => animals.list(
            filter: any(named: 'filter'),
            sort: any(named: 'sort'),
            expand: any(named: 'expand'),
            fields: any(named: 'fields'),
          ),
        );
        final call = verify(
          () =>
              animals.byIds(captureAny(), fields: captureAny(named: 'fields')),
        ).captured;
        expect((call[0]! as Iterable<String>).toList(), ['a1']);
        expect(call[1], 'id,species,name');
      },
    );
  });
}
