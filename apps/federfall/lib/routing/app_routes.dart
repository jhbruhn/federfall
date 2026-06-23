/// Route paths used across the app. Centralised so redirects and navigation
/// calls reference one source of truth.
abstract final class AppRoutes {
  /// Transient gate shown while server config / auth status resolve.
  static const splash = '/splash';

  /// Native-only first-run server URL entry (FED-3.0).
  static const setup = '/setup';

  /// Sign-in screen (FED-3.1).
  static const login = '/login';

  /// Authenticated app shell / home (FED-3.3).
  static const home = '/';
}
