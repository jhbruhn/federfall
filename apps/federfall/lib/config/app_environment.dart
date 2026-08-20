import 'package:zugvogel_pb_client/zugvogel_pb_client.dart';

// MapMode now lives in zugvogel_pb_client (eiermann-d2a.4): it is part of the
// /info wire contract, not of this app's configuration. Re-exported under the
// same name so every call site keeps working — declaring a second enum here
// would make the two structurally identical and mutually unassignable, which is
// exactly the error this replaces.
export 'package:zugvogel_pb_client/zugvogel_pb_client.dart' show MapMode;

/// Build-time application configuration.
///
/// Values are injected via `--dart-define-from-file=dart_defines/<flavor>.json`
/// (see the `dart_defines/` directory) and read here through
/// `String.fromEnvironment`. Because these are compile-time constants they are
/// tree-shaken and safe to reference anywhere.
enum AppFlavor { development, staging, production }

abstract final class AppEnvironment {
  /// Raw flavor name from the `FLAVOR` define (defaults to development so a
  /// bare `flutter run` without a defines file still works).
  static const String flavorName = String.fromEnvironment(
    'FLAVOR',
    defaultValue: 'development',
  );

  /// Parsed [AppFlavor].
  static AppFlavor get flavor => switch (flavorName) {
    'production' => AppFlavor.production,
    'staging' => AppFlavor.staging,
    _ => AppFlavor.development,
  };

  /// Human-facing app name for the current flavor (e.g. `[DEV] Federfall`).
  static const String appName = String.fromEnvironment(
    'APP_NAME',
    defaultValue: 'Federfall',
  );

  /// Optional build-time PocketBase base URL.
  ///
  /// Mainly a dev/web convenience (development points at the local
  /// containerized backend on `http://localhost:8090`). At runtime the base URL
  /// is resolved per platform (FED-2.1): on web from the app's own serving
  /// origin, on native from the user-configured server URL (FED-3.0). When this
  /// override is non-empty it can seed that resolution.
  static const String pocketbaseUrlOverride = String.fromEnvironment(
    'POCKETBASE_URL',
  );

  /// Whether a build-time PocketBase URL override was provided.
  static bool get hasPocketbaseUrlOverride => pocketbaseUrlOverride.isNotEmpty;

  // The MAP_* defines below are only the FALLBACK map source. The server can
  // prescribe one at runtime through `/api/federfall/info` (federfall-el1f) —
  // it has to be able to, since these constants are baked into the web bundle
  // and the APK and are not configuration at all on a published image. Read the
  // effective values through `MapConfig`/`mapConfigProvider`, never from here
  // directly; these apply when the server prescribes nothing.

  /// Raw `MAP_MODE` define (defaults to `raster`, see [mapMode]).
  static const String mapModeName = String.fromEnvironment(
    'MAP_MODE',
    defaultValue: 'raster',
  );

  /// Which map rendering path the find-location map (FED-4.2) uses.
  ///
  /// `raster` (the default) draws a classic `{z}/{x}/{y}.png` tile server
  /// ([mapTileUrl]) as plain images. `vector` renders a MapLibre-style vector
  /// tile source ([mapStyleUrl], e.g. OpenFreeMap) through `vector_map_tiles`.
  ///
  /// Raster is the default because `vector_map_tiles` rasterizes on the Dart
  /// canvas with no GPU path, which costs both frame rate and label quality
  /// next to blitting ready-made images. Vector stays supported — it is what a
  /// self-hosted OpenFreeMap/OpenMapTiles stack serves, and it is cheaper to
  /// host — so operators who prefer it set `FEDERFALL_MAP_MODE=vector`.
  static MapMode get mapMode => switch (mapModeName) {
    'vector' => MapMode.vector,
    _ => MapMode.raster,
  };

  /// MapLibre style JSON URL used in [MapMode.vector] mode. Defaults to
  /// OpenFreeMap's "liberty" style (self-hostable, no API key required).
  static const String mapStyleUrl = String.fromEnvironment(
    'MAP_STYLE_URL',
    defaultValue: 'https://tiles.openfreemap.org/styles/liberty',
  );

  /// Raster tile URL template used in [MapMode.raster] mode. Defaults to the
  /// public OSM tile server.
  ///
  /// Since [mapMode] defaults to raster, this is what a stock deployment
  /// requests. The OSM Tile Usage Policy does not really cover an application
  /// backend, so an operator with more than a handful of users is expected to
  /// repoint it (`FEDERFALL_MAP_TILE_URL`, no rebuild needed) at a self-hosted
  /// or commercial tile server — see docs/DEPLOYMENT.md. What the app owes the
  /// policy either way it already does: identifies itself in
  /// `MapTileLayer._userAgentPackageName`, caches tiles on disk, and never
  /// bulk-prefetches.
  static const String mapTileUrl = String.fromEnvironment(
    'MAP_TILE_URL',
    defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  );

  /// Attribution shown on the map, matching whichever of [mapStyleUrl] /
  /// [mapTileUrl] is active for the current [mapMode] — so the default credits
  /// OSM, whose raster tiles [mapTileUrl] points at. Switching [mapMode] to
  /// `vector` without a matching style keeps this correct too: OpenFreeMap
  /// serves OpenStreetMap data. Any *other* provider needs its own credit,
  /// which is why the runtime override (federfall-el1f) refuses to apply a URL
  /// without one.
  static const String mapAttribution = String.fromEnvironment(
    'MAP_ATTRIBUTION',
    defaultValue: '© OpenStreetMap contributors',
  );

  /// Copyright/licence page the map attribution links to. Defaults to the OSM
  /// copyright page, which the OSMF attribution guidelines ask interactive
  /// maps to link to. Change it alongside [mapStyleUrl]/[mapTileUrl]/
  /// [mapAttribution] when pointing at another provider.
  static const String mapAttributionUrl = String.fromEnvironment(
    'MAP_ATTRIBUTION_URL',
    defaultValue: 'https://www.openstreetmap.org/copyright',
  );

  static bool get isProduction => flavor == AppFlavor.production;
}
