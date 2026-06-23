import 'package:federfall_models/src/converters.dart';
import 'package:federfall_models/src/models/geo_point.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:pocketbase/pocketbase.dart';

part 'aviary.freezed.dart';

/// A named permanent-care enclosure (Voliere) where non-releasable birds live
/// as residents.
@freezed
abstract class Aviary with _$Aviary {
  const factory Aviary({
    required String id,
    required String name,
    String? keeper,
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
      keeper: pbString(d['keeper']),
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
