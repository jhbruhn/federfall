import 'package:freezed_annotation/freezed_annotation.dart';

part 'geo_point.freezed.dart';

/// A geographic pin, mirroring a PocketBase `geoPoint` field (`{lon, lat}`).
///
/// PocketBase represents an unset pin as `{lon: 0, lat: 0}`; [fromPb] treats
/// that sentinel as "no pin" and returns `null`.
@freezed
abstract class GeoPoint with _$GeoPoint {
  const factory GeoPoint({
    required double lon,
    required double lat,
  }) = _GeoPoint;

  /// Parses a raw PocketBase geoPoint map, or `null` when unset.
  static GeoPoint? fromPb(Object? raw) {
    if (raw is! Map) return null;
    final lon = (raw['lon'] as num?)?.toDouble();
    final lat = (raw['lat'] as num?)?.toDouble();
    if (lon == null || lat == null) return null;
    if (lon == 0 && lat == 0) return null;
    return GeoPoint(lon: lon, lat: lat);
  }
}
