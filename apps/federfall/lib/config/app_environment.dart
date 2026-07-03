/// Build-time application configuration.
///
/// Values are injected via `--dart-define-from-file=dart_defines/<flavor>.json`
/// (see the `dart_defines/` directory) and read here through
/// `String.fromEnvironment`. Because these are compile-time constants they are
/// tree-shaken and safe to reference anywhere.
enum AppFlavor { development, staging, production }

/// Map tile rendering path, see [AppEnvironment.mapMode].
enum MapMode { vector, raster }

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

  /// Raw `MAP_MODE` define (defaults to `vector`, see [mapMode]).
  static const String mapModeName = String.fromEnvironment(
    'MAP_MODE',
    defaultValue: 'vector',
  );

  /// Which map rendering path the find-location map (FED-4.2) uses.
  ///
  /// `vector` (the default) renders a MapLibre-style vector tile source
  /// ([mapStyleUrl], e.g. OpenFreeMap) through `vector_map_tiles`. `raster`
  /// falls back to a classic `{z}/{x}/{y}.png` tile server ([mapTileUrl]) —
  /// set it for self-hosted or commercial raster tile providers.
  static MapMode get mapMode => switch (mapModeName) {
    'raster' => MapMode.raster,
    _ => MapMode.vector,
  };

  /// MapLibre style JSON URL used in [MapMode.vector] mode. Defaults to
  /// OpenFreeMap's "liberty" style (self-hostable, no API key required).
  static const String mapStyleUrl = String.fromEnvironment(
    'MAP_STYLE_URL',
    defaultValue: 'https://tiles.openfreemap.org/styles/liberty',
  );

  /// Raster tile URL template used in [MapMode.raster] mode. Defaults to the
  /// public OSM tile server — point at a self-hosted tile server in
  /// production to respect OSM's usage policy.
  static const String mapTileUrl = String.fromEnvironment(
    'MAP_TILE_URL',
    defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  );

  /// Attribution shown on the map, matching whichever of [mapStyleUrl] /
  /// [mapTileUrl] is active for the current [mapMode].
  static const String mapAttribution = String.fromEnvironment(
    'MAP_ATTRIBUTION',
    defaultValue: 'OpenFreeMap © OpenMapTiles Data from OpenStreetMap',
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
