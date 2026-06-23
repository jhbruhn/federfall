/// Route paths used across the app. Centralised so redirects and navigation
/// calls reference one source of truth.
abstract final class AppRoutes {
  /// Transient gate shown while server config / auth status resolve.
  static const splash = '/splash';

  /// Native-only first-run server URL entry (FED-3.0).
  static const setup = '/setup';

  /// Sign-in screen (FED-3.1).
  static const login = '/login';

  /// Authenticated app shell / home — the carer's case list (FED-3.4).
  static const home = '/';

  /// Create-case form (FED-3.4).
  static const newCase = '/cases/new';

  /// Case detail, parameterised by id (FED-3.4). Registered after [newCase] so
  /// the literal `/cases/new` wins over this pattern.
  static const caseDetailPattern = '/cases/:id';

  /// Builds the concrete case-detail path for [id].
  static String caseDetail(String id) => '/cases/$id';

  /// Signed-in user's profile (FED-3.3).
  static const profile = '/profile';

  /// Supervisor-only admin area (FED-3.3 / FED-3.2 invites).
  static const admin = '/admin';

  /// Password-reset confirmation, reached from the invite email (FED-3.2).
  /// Public: usable without a session.
  static const confirmReset = '/auth/confirm-reset';
}
