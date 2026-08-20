import 'package:flutter/widgets.dart';
import 'package:zugvogel_ui/zugvogel_ui.dart' as zv;

// The tile layer moved to zugvogel_ui (eiermann-d2a.11) with both rendering
// paths intact, and it still takes its source from mapConfigProvider — the
// server's prescription when it sends one, otherwise this app's build-time
// defines (federfall-el1f).
//
// One thing had to become injected: the user-agent package name. The OSM Tile
// Usage Policy asks a client to identify the application making the request,
// and a shared package cannot answer that question — a library that named
// itself would have every Zugvogel app claim to be the same one, and a library
// that named federfall would make eiermann lie. So the library requires it, and
// this wrapper supplies the value the widget used to hardcode.

/// The map's tile layer, configured once for the whole app.
///
/// The source comes from `mapConfigProvider` — the server's prescription when
/// it sends one, otherwise the build-time defines (federfall-el1f). Picks a
/// rendering path from its `MapConfig.mode`:
/// - `raster` (default): a classic raster `TileLayer`. Enables flutter_map's
///   built-in disk caching explicitly, which the OpenStreetMap Tile Usage
///   Policy requires when pointed at OSM's public raster tiles (the policy's
///   primary requirement, and the stock default points there).
/// - `vector`: loads a MapLibre style (e.g. OpenFreeMap) and renders it through
///   `vector_map_tiles`, which brings its own file-based tile cache. Not the
///   default: it rasterizes on the Dart canvas with no GPU path, so both frame
///   rate and label quality trail plain image tiles.
///
/// Note: while pointed at a public/free tile provider, do NOT pre-fetch or
/// bulk-download tiles (e.g. to seed an offline area) — most usage policies
/// forbid it. A self-hosted/commercial tile server would lift that
/// restriction.
class MapTileLayer extends StatelessWidget {
  const MapTileLayer({super.key});

  /// How this app identifies itself in tile requests, as the OSM Tile Usage
  /// Policy requires. The Android application id, so a maintainer reading a
  /// tile server's log can tell which app the traffic came from.
  static const String userAgentPackageName = 'de.jhbruhn.federfall';

  @override
  Widget build(BuildContext context) =>
      const zv.MapTileLayer(userAgentPackageName: userAgentPackageName);
}
