import 'package:federfall/data/repository_providers.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show DateTimeRange;
import 'package:latlong2/latlong.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'intake_map_providers.g.dart';

/// One case's find-location pin, projected for the intake overview map
/// (federfall-xr8t).
@immutable
class IntakeLocation {
  const IntakeLocation({
    required this.caseId,
    required this.point,
    this.caseNumber,
    this.animalName,
    this.species,
    this.city,
    this.admittedAt,
  });

  final String caseId;
  final LatLng point;
  final String? caseNumber;
  final String? animalName;
  final String? species;
  final String? city;
  final DateTime? admittedAt;
}

/// Pure projection of [cases] into map pins (federfall-xr8t): keeps only
/// cases with a resolved find-location, optionally restricted to
/// [admittedRange] (cases with no `admittedAt` are dropped once a range is
/// set, since they can't be placed in it). Kept separate from the provider so
/// it can be unit-tested without PocketBase, mirroring `computeStatistics`.
List<IntakeLocation> filterIntakeLocations({
  required List<Case> cases,
  required Map<String, String> speciesByAnimal,
  Map<String, String> nameByAnimal = const {},
  DateTimeRange? admittedRange,
}) {
  final locations = <IntakeLocation>[];
  for (final c in cases) {
    final geo = c.findGeo;
    if (geo == null) continue;
    final admittedAt = c.admittedAt;
    if (admittedRange != null) {
      if (admittedAt == null) continue;
      if (admittedAt.isBefore(admittedRange.start) ||
          admittedAt.isAfter(admittedRange.end)) {
        continue;
      }
    }
    locations.add(
      IntakeLocation(
        caseId: c.id,
        point: LatLng(geo.lat, geo.lon),
        caseNumber: c.caseNumber,
        animalName: nameByAnimal[c.animal],
        species: speciesByAnimal[c.animal],
        city: c.city,
        admittedAt: admittedAt,
      ),
    );
  }
  return locations;
}

/// Find-location pins for the intake overview map (federfall-xr8t), for
/// cases the user may read — org-wide for coordinators/supervisors, the same
/// server-enforced scope as the `statistics` provider. [admittedRange]
/// filters by admission date; `null` means all time.
@riverpod
Future<List<IntakeLocation>> intakeLocations(
  Ref ref, {
  DateTimeRange? admittedRange,
}) async {
  final casesRepo = await ref.watch(casesRepositoryProvider.future);
  final animalsRepo = await ref.watch(animalsRepositoryProvider.future);

  final cases = await casesRepo.list();
  final animals = await animalsRepo.list();

  return filterIntakeLocations(
    cases: cases,
    speciesByAnimal: {for (final a in animals) a.id: a.species},
    nameByAnimal: {
      for (final a in animals)
        if (a.name case final name? when name.isNotEmpty) a.id: name,
    },
    admittedRange: admittedRange,
  );
}
