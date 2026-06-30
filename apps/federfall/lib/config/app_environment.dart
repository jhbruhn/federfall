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

  /// Map tile URL template for the find-location map (FED-4.2). Configurable at
  /// build time; defaults to the public OSM tile server. Point at a self-hosted
  /// tile server in production to respect OSM's usage policy.
  static const String mapTileUrl = String.fromEnvironment(
    'MAP_TILE_URL',
    defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  );

  /// Attribution shown on the map, matching [mapTileUrl].
  static const String mapAttribution = String.fromEnvironment(
    'MAP_ATTRIBUTION',
    defaultValue: '© OpenStreetMap contributors',
  );

  /// Copyright/licence page the map attribution links to. Defaults to the OSM
  /// copyright page, which the OSMF attribution guidelines ask interactive maps
  /// to link to. Change it alongside [mapTileUrl]/[mapAttribution] when pointing
  /// at another tile provider.
  static const String mapAttributionUrl = String.fromEnvironment(
    'MAP_ATTRIBUTION_URL',
    defaultValue: 'https://www.openstreetmap.org/copyright',
  );

  static bool get isProduction => flavor == AppFlavor.production;
}
