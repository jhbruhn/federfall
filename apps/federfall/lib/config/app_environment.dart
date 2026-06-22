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

  static bool get isProduction => flavor == AppFlavor.production;
}
