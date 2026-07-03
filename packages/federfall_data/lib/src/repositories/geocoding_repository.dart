import 'dart:async';

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

  /// Parses one entry of the proxy's JSON, or returns `null` when it is not
  /// a map or lacks numeric coordinates. The proxy relays a third-party
  /// geocoder, so a malformed entry must be skipped — never defaulted to a
  /// plausible-looking (0,0) pin that a user could save into `find_geo`
  /// (which `GeoPoint.fromPb` would then read back as "no pin").
  static GeoResult? tryParse(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final lat = raw['lat'];
    final lon = raw['lon'];
    if (lat is! num || lon is! num) return null;
    return GeoResult(
      lat: lat.toDouble(),
      lon: lon.toDouble(),
      displayName: (raw['displayName'] as String?) ?? '',
      city: (raw['city'] as String?) ?? '',
      region: (raw['region'] as String?) ?? '',
    );
  }

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
  PbGeocodingRepository(
    this.pb, {
    this.networkTimeout = const Duration(seconds: 15),
  });

  final PocketBase pb;

  /// Caps a single request so an unreachable server fails fast with a network
  /// error instead of hanging on the OS TCP timeout (minutes) — same
  /// online-only contract as `PbRepository`.
  final Duration networkTimeout;

  @override
  Future<List<GeoResult>> forward(String query) async {
    return _guard(() async {
      final res = await pb.send<Map<String, dynamic>>(
        '/api/federfall/geocode',
        query: {'q': query},
      );
      final results = (res['results'] as List?) ?? const [];
      return results.map(GeoResult.tryParse).whereType<GeoResult>().toList();
    });
  }

  @override
  Future<GeoResult?> reverse(double lat, double lon) async {
    return _guard(() async {
      final res = await pb.send<Map<String, dynamic>>(
        '/api/federfall/geocode/reverse',
        query: {'lat': '$lat', 'lon': '$lon'},
      );
      // A malformed result reads as "unresolved" — same as no result.
      return GeoResult.tryParse(res['result']);
    });
  }

  /// Mirrors `PbRepository._guard`: timeout → network, SDK errors →
  /// [RepositoryException], and any other failure (e.g. an unexpected
  /// response shape) wrapped so the UI error states get a stable type.
  Future<R> _guard<R>(Future<R> Function() op) async {
    try {
      return await op().timeout(networkTimeout);
    } on TimeoutException {
      throw const RepositoryException(
        'Could not reach the server',
        kind: RepositoryErrorKind.network,
      );
    } on ClientException catch (e) {
      throw RepositoryException.fromClient(e);
    } on RepositoryException {
      rethrow;
    } on Object catch (e) {
      throw RepositoryException('Unexpected repository failure: $e', cause: e);
    }
  }
}
