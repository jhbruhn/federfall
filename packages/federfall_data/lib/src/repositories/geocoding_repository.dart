import 'package:federfall_data/src/repository_exception.dart';
import 'package:pocketbase/pocketbase.dart';

/// A geocoding candidate: a pin plus the address details resolved for it.
class GeoResult {
  const GeoResult({
    required this.lat,
    required this.lon,
    this.displayName = '',
    this.city = '',
    this.region = '',
  });

  factory GeoResult.fromJson(Map<String, dynamic> json) => GeoResult(
    lat: (json['lat'] as num?)?.toDouble() ?? 0,
    lon: (json['lon'] as num?)?.toDouble() ?? 0,
    displayName: (json['displayName'] as String?) ?? '',
    city: (json['city'] as String?) ?? '',
    region: (json['region'] as String?) ?? '',
  );

  final double lat;
  final double lon;
  final String displayName;
  final String city;
  final String region;
}

/// Address ⇄ coordinate lookups for the find-location map (FED-4.2).
///
/// An interface so the backing geocoder can be swapped without touching the
/// UI. The default implementation goes through the Federfall backend rather
/// than calling a geocoder directly (keeps the contact/User-Agent and
/// rate-limiting server-side and avoids browser CORS).
abstract interface class GeocodingRepository {
  /// Forward geocode: free-text [query] → candidate locations.
  Future<List<GeoResult>> forward(String query);

  /// Reverse geocode: a pin → its resolved address, or `null` if unresolved.
  Future<GeoResult?> reverse(double lat, double lon);
}

/// [GeocodingRepository] backed by the backend proxy routes (`geocode.pb.js`).
class PbGeocodingRepository implements GeocodingRepository {
  PbGeocodingRepository(this.pb);

  final PocketBase pb;

  @override
  Future<List<GeoResult>> forward(String query) async {
    return _guard(() async {
      final res = await pb.send<Map<String, dynamic>>(
        '/api/federfall/geocode',
        query: {'q': query},
      );
      final results = (res['results'] as List?) ?? const [];
      return results
          .cast<Map<String, dynamic>>()
          .map(GeoResult.fromJson)
          .toList();
    });
  }

  @override
  Future<GeoResult?> reverse(double lat, double lon) async {
    return _guard(() async {
      final res = await pb.send<Map<String, dynamic>>(
        '/api/federfall/geocode/reverse',
        query: {'lat': '$lat', 'lon': '$lon'},
      );
      final result = res['result'] as Map<String, dynamic>?;
      return result == null ? null : GeoResult.fromJson(result);
    });
  }

  Future<R> _guard<R>(Future<R> Function() op) async {
    try {
      return await op();
    } on ClientException catch (e) {
      throw RepositoryException.fromClient(e);
    }
  }
}
