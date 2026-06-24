/// Route paths used across the app. Centralised so redirects and navigation
/// calls reference one source of truth.
abstract final class AppRoutes {
  /// Transient gate shown while server config / auth status resolve.
  static const splash = '/splash';

  /// Native-only first-run server URL entry (FED-3.0).
  static const setup = '/setup';

  /// Sign-in screen (FED-3.1).
  static const login = '/login';

  /// Dashboard tab of the navigation shell (FED-7.0 / FED-7.1).
  static const dashboard = '/dashboard';

  /// Today / worklist — the carer's derived to-do list (UX Phase D, cr3.2).
  static const today = '/today';

  /// Cases tab — the carer's case list (FED-3.4).
  static const cases = '/cases';

  /// Animals tab — the animals registry (FED-7.0 / FED-7.5).
  static const animals = '/animals';

  /// Aviaries tab — the aviary registry (FED-6.1).
  static const aviaries = '/aviaries';

  /// Builds the concrete aviary-detail path for [id] (FED-6.2).
  static String aviaryDetail(String id) => '/aviaries/$id';

  /// Builds the concrete animal-detail path for [id] (FED-7.6).
  static String animalDetail(String id) => '/animals/$id';

  /// Default authenticated landing destination.
  static const String home = cases;

  /// Create-case form (FED-3.4).
  static const newCase = '/cases/new';

  /// Create-case form pre-linked to an existing animal (5yg.3).
  static String newCaseForAnimal(String animalId) =>
      '/cases/new?animal=$animalId';

  /// Builds the concrete case-detail path for [id] (FED-3.4).
  static String caseDetail(String id) => '/cases/$id';

  // Relative sub-path segments, used when declaring the case/animal detail
  // routes as children of their navigation-shell branch (so the address bar
  // and back button track the pushed detail page — go_router does not update
  // the URL for routes pushed as siblings of a StatefulShellRoute).

  /// `new` — create-case form, child of the cases branch.
  static const newCaseSegment = 'new';

  /// `:id` — detail page, child of the cases / animals branch.
  static const detailSegment = ':id';

  /// Signed-in user's profile (FED-3.3).
  static const profile = '/profile';

  /// Management hub — admin/reporting landing for supervisors (federfall-dri).
  static const admin = '/admin';

  /// Supervisor-only team roster + invites, under the management hub (FED-3.3).
  static const manageTeam = '/admin/team';

  /// Supervisor-only organisation settings (UX Phase A).
  static const orgSettings = '/admin/org-settings';

  /// Supervisor-only condition code-list editor (UX Phase A).
  static const conditionsAdmin = '/admin/conditions';

  /// Reporting statistics, for coordinators/supervisors (FED-7.2).
  static const statistics = '/statistics';

  /// Password-reset confirmation, reached from the invite email (FED-3.2).
  /// Public: usable without a session.
  static const confirmReset = '/auth/confirm-reset';
}
