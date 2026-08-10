import 'package:federfall_models/src/converters.dart';
import 'package:federfall_models/src/models/geo_point.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:pocketbase/pocketbase.dart';

part 'aviary.freezed.dart';

/// A named permanent-care enclosure (Voliere) where non-releasable birds live
/// as residents.
///
/// [keeper] is the member responsible for the enclosure, and is required by the
/// schema since 1700000076 (federfall-q7ks.1): the custody model resolves a
/// resident's write authority through it, so an enclosure without one would
/// hold birds nobody could write about. It stays a plain `String` rather than a
/// nullable one for that reason — empty is not a state the server offers. A row
/// from a pre-1700000076 server maps to `''`, which resolves to no member and
/// renders as an absent keeper rather than throwing.
@freezed
abstract class Aviary with _$Aviary {
  const factory Aviary({
    required String id,
    required String name,
    required String keeper,
    String? location,
    GeoPoint? locationGeo,
    int? capacity,
    @Default(true) bool active,
    String? notes,
    String? org,
    DateTime? created,
    DateTime? updated,
  }) = _Aviary;

  factory Aviary.fromRecord(RecordModel r) {
    final d = r.data;
    return Aviary(
      id: r.id,
      name: pbString(d['name']) ?? '',
      keeper: pbString(d['keeper']) ?? '',
      location: pbString(d['location']),
      locationGeo: GeoPoint.fromPb(d['location_geo']),
      capacity: pbInt(d['capacity']),
      active: pbBool(d['active']),
      notes: pbString(d['notes']),
      org: pbString(d['org']),
      created: pbDate(d['created']),
      updated: pbDate(d['updated']),
    );
  }
}

/// A single residency period in an [Aviary] (federfall-d5co.1): an
/// append-only ledger entry mirroring `animals.current_aviary` history.
/// [endedAt] unset means this is the animal's current residency.
@freezed
abstract class AviaryStay with _$AviaryStay {
  const factory AviaryStay({
    required String id,
    required String animal,
    required String aviary,
    DateTime? startedAt,
    DateTime? endedAt,
    String? org,
    DateTime? created,
    DateTime? updated,
  }) = _AviaryStay;

  factory AviaryStay.fromRecord(RecordModel r) {
    final d = r.data;
    return AviaryStay(
      id: r.id,
      animal: pbString(d['animal']) ?? '',
      aviary: pbString(d['aviary']) ?? '',
      startedAt: pbDate(d['started_at']),
      endedAt: pbDate(d['ended_at']),
      org: pbString(d['org']),
      created: pbDate(d['created']),
      updated: pbDate(d['updated']),
    );
  }
}
