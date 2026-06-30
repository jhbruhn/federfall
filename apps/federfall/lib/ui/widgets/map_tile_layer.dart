import 'package:federfall/config/app_environment.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

/// The map's raster [TileLayer], configured once for the whole app.
///
/// Centralises the tile URL ([AppEnvironment.mapTileUrl]) and the
/// `User-Agent` package name, and enables flutter_map's built-in disk caching
/// explicitly. Caching keeps repeat views off the network and is required by
/// the OpenStreetMap Tile Usage Policy: tiles are cached per their HTTP cache
/// headers (the policy's primary requirement) on native, while the browser
/// caches on web. The cache provider is a process-wide singleton, so every map
/// shares one store.
///
/// Note: while pointed at the public OSM tile server, do NOT pre-fetch or
/// bulk-download tiles (e.g. to seed an offline area) — the policy forbids it.
/// A self-hosted/commercial tile server would lift that restriction.
class MapTileLayer extends StatelessWidget {
  const MapTileLayer({super.key});

  /// Identifies the app in tile requests, as the OSM policy requires.
  static const String _userAgentPackageName = 'de.jhbruhn.federfall';

  @override
  Widget build(BuildContext context) => TileLayer(
        urlTemplate: AppEnvironment.mapTileUrl,
        userAgentPackageName: _userAgentPackageName,
        tileProvider: NetworkTileProvider(
          cachingProvider: BuiltInMapCachingProvider.getOrCreateInstance(),
        ),
      );
}
