import 'package:federfall/features/statistics/intake_map_providers.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_test/flutter_test.dart';

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
}
