import 'package:federfall/config/app_environment.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

/// The map's tile layer, configured once for the whole app.
///
/// Picks a rendering path via [AppEnvironment.mapMode]:
/// - `vector` (default): loads a MapLibre style ([AppEnvironment.mapStyleUrl],
///   e.g. OpenFreeMap) and renders it through `vector_map_tiles`.
/// - `raster`: a classic raster [TileLayer] pointed at
///   [AppEnvironment.mapTileUrl], for self-hosted or commercial raster tile
///   servers. Enables flutter_map's built-in disk caching explicitly, which
///   the OpenStreetMap Tile Usage Policy requires when pointed at OSM's
///   public raster tiles (the policy's primary requirement); the vector path
///   gets its own file-based tile cache from `vector_map_tiles`.
///
/// Note: while pointed at a public/free tile provider, do NOT pre-fetch or
/// bulk-download tiles (e.g. to seed an offline area) — most usage policies
/// forbid it. A self-hosted/commercial tile server would lift that
/// restriction.
class MapTileLayer extends StatefulWidget {
  const MapTileLayer({super.key});

  @override
  State<MapTileLayer> createState() => _MapTileLayerState();
}

class _MapTileLayerState extends State<MapTileLayer> {
  /// Identifies the app in tile requests, as the OSM policy requires.
  static const String _userAgentPackageName = 'de.jhbruhn.federfall';

  final Future<Style>? _style = AppEnvironment.mapMode == MapMode.vector
      ? StyleReader(uri: AppEnvironment.mapStyleUrl).read()
      : null;

  @override
  Widget build(BuildContext context) {
    if (AppEnvironment.mapMode == MapMode.raster) {
      return TileLayer(
        urlTemplate: AppEnvironment.mapTileUrl,
        userAgentPackageName: _userAgentPackageName,
        tileProvider: NetworkTileProvider(
          cachingProvider: BuiltInMapCachingProvider.getOrCreateInstance(),
        ),
      );
    }
    return FutureBuilder<Style>(
      future: _style,
      builder: (context, snapshot) {
        final style = snapshot.data;
        if (style == null) return const SizedBox.shrink();
        return VectorTileLayer(
          tileProviders: style.providers,
          theme: style.theme,
          sprites: style.sprites,
        );
      },
    );
  }
}
