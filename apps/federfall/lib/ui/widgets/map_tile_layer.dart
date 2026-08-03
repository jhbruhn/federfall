import 'package:federfall/config/app_environment.dart';
import 'package:federfall/config/map_config.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

/// The map's tile layer, configured once for the whole app.
///
/// The source comes from [mapConfigProvider] — the server's prescription when
/// it sends one, otherwise the build-time defines (federfall-el1f). Picks a
/// rendering path from its [MapConfig.mode]:
/// - `vector` (default): loads a MapLibre style (e.g. OpenFreeMap) and renders
///   it through `vector_map_tiles`.
/// - `raster`: a classic raster [TileLayer], for self-hosted or commercial
///   raster tile servers. Enables flutter_map's built-in disk caching
///   explicitly, which the OpenStreetMap Tile Usage Policy requires when
///   pointed at OSM's public raster tiles (the policy's primary requirement);
///   the vector path gets its own file-based tile cache from
///   `vector_map_tiles`.
///
/// Note: while pointed at a public/free tile provider, do NOT pre-fetch or
/// bulk-download tiles (e.g. to seed an offline area) — most usage policies
/// forbid it. A self-hosted/commercial tile server would lift that
/// restriction.
class MapTileLayer extends ConsumerWidget {
  const MapTileLayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(mapConfigProvider);
    // Keyed by the config so a change REPLACES the layer's State rather than
    // updating it: the vector path starts reading its style in initState, and
    // that read is not something an in-place rebuild can redo. The config does
    // change under a live widget — `/info` resolving after a warm start, or the
    // user switching servers on native.
    return _MapTileLayerBody(config: config, key: ValueKey(config));
  }
}

class _MapTileLayerBody extends StatefulWidget {
  const _MapTileLayerBody({required this.config, super.key});

  final MapConfig config;

  @override
  State<_MapTileLayerBody> createState() => _MapTileLayerBodyState();
}

class _MapTileLayerBodyState extends State<_MapTileLayerBody> {
  /// Identifies the app in tile requests, as the OSM policy requires.
  static const String _userAgentPackageName = 'de.jhbruhn.federfall';

  // apiKey is what lets a commercial style work at all: StyleReader substitutes
  // it for the `{key}` token in the style AND in the source/sprite/glyph URLs
  // the style itself names, and resolves `mapbox://` URIs from it.
  late final Future<Style>? _style = widget.config.mode == MapMode.vector
      ? StyleReader(uri: widget.config.url, apiKey: widget.config.apiKey).read()
      : null;

  @override
  Widget build(BuildContext context) {
    if (widget.config.mode == MapMode.raster) {
      return TileLayer(
        urlTemplate: widget.config.rasterUrl,
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
