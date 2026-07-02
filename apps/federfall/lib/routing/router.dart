import 'package:federfall/core/auth/auth_status.dart';
import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/auth/roles.dart';
import 'package:federfall/core/server/server_config.dart';
import 'package:federfall/core/server/server_config_controller.dart';
import 'package:federfall/core/server/server_info_provider.dart';
import 'package:federfall/features/admin/codelist_admin.dart';
import 'package:federfall/features/admin/codelist_specs.dart';
import 'package:federfall/features/admin/management_screen.dart';
import 'package:federfall/features/admin/org_settings_screen.dart';
import 'package:federfall/features/admin/team_screen.dart';
import 'package:federfall/features/animals/animal_detail_screen.dart';
import 'package:federfall/features/animals/animals_screen.dart';
import 'package:federfall/features/auth/confirm_reset_screen.dart';
import 'package:federfall/features/auth/login_screen.dart';
import 'package:federfall/features/auth/pending_approval_screen.dart';
import 'package:federfall/features/aviaries/aviaries_screen.dart';
import 'package:federfall/features/aviaries/aviary_detail_screen.dart';
import 'package:federfall/features/cases/case_detail_screen.dart';
import 'package:federfall/features/cases/cases_browser.dart';
import 'package:federfall/features/cases/cases_screen.dart';
import 'package:federfall/features/cases/new_case_screen.dart';
import 'package:federfall/features/dashboard/dashboard_screen.dart';
import 'package:federfall/features/home/nav_shell.dart';
import 'package:federfall/features/profile/profile_screen.dart';
import 'package:federfall/features/server_setup/setup_screen.dart';
import 'package:federfall/features/startup/splash_screen.dart';
import 'package:federfall/features/statistics/statistics_screen.dart';
import 'package:federfall/features/worklist/today_screen.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/routing/app_routes.dart';
import 'package:federfall/routing/not_found_screen.dart';
import 'package:federfall/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'router.g.dart';

/// The app router and its redirect gate.
///
/// Two-stage gate, re-run whenever server config or auth status change:
///   1. **native only** — no server configured → `/setup` (web is always
///      configured via its serving origin, so this never fires there);
///   2. unauthenticated → `/login`;
///   3. otherwise the authenticated home shell.
///
/// While either signal is still resolving the user waits on `/splash`.
@Riverpod(keepAlive: true)
GoRouter router(Ref ref) {
  // Bump a Listenable whenever a gating signal changes so go_router re-runs the
  // redirect. Listening here also forces both async providers to initialise.
  final refresh = ValueNotifier<int>(0);
  ref
    ..listen(serverConfigControllerProvider, (_, _) => refresh.value++)
    ..listen(serverInfoProvider, (_, _) => refresh.value++)
    ..listen(authStatusProvider, (_, _) => refresh.value++)
    ..listen(currentUserProvider, (_, _) => refresh.value++)
    ..onDispose(refresh.dispose);

  // Create routes (and the transient browser) live on the root navigator so
  // they render full-screen over everything.
  final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

  // Each canonical list-detail surface owns a nested pane navigator (via a
  // `ShellRoute`) so the section root and the selected detail can sit side by
  // side on expanded widths, and stack (with a native push) on compact ones.
  final casesPaneKey = GlobalKey<NavigatorState>(debugLabel: 'casesPane');
  final animalsPaneKey = GlobalKey<NavigatorState>(debugLabel: 'animalsPane');
  final aviariesPaneKey = GlobalKey<NavigatorState>(debugLabel: 'aviariesPane');

  // Each section's list widget appears in one of two tree positions depending
  // on width: the pane navigator's root on compact, the shell's left pane on
  // expanded. Sharing one GlobalKey between both positions makes crossing the
  // breakpoint *move* the mounted list instead of remounting it, so scroll
  // position and in-progress search/filter state survive a tablet rotation or
  // window resize (federfall-8bh2). Both positions switch on the same
  // `context.isExpanded`, so exactly one of them builds the key per frame.
  final casesListKey = GlobalKey(debugLabel: 'casesList');
  final animalsListKey = GlobalKey(debugLabel: 'animalsList');
  final aviariesListKey = GlobalKey(debugLabel: 'aviariesList');

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: AppRoutes.home,
    refreshListenable: refresh,
    redirect: (context, state) => _gate(ref, state.uri),
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (_, _) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.setup,
        builder: (_, _) => const SetupScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (_, _) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.pending,
        builder: (_, _) => const PendingApprovalScreen(),
      ),
      // Adaptive top-level navigation shell (FED-7.0): Dashboard, Cases,
      // Animals. Each destination is a branch so its state survives switching.
      StatefulShellRoute.indexedStack(
        builder: (_, _, navigationShell) =>
            NavShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.dashboard,
                builder: (_, _) => const DashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            initialLocation: AppRoutes.cases,
            routes: [
              ShellRoute(
                navigatorKey: casesPaneKey,
                builder: (_, _, child) => ListDetailShell(
                  list: CasesScreen(key: casesListKey),
                  detailChild: child,
                ),
                routes: [
                  GoRoute(
                    path: AppRoutes.cases,
                    // Expanded: the list is the shell's left pane, so the pane
                    // navigator's root is the "nothing selected" placeholder.
                    // Compact: the pane navigator IS the list.
                    builder: (context, _) => context.isExpanded
                        ? DetailPanePlaceholder(
                            icon: Icons.medical_information_outlined,
                            message: context.l10n.listDetailSelectCase,
                          )
                        : CasesScreen(key: casesListKey),
                    routes: [
                      // `/cases/new` — full-screen over the shell; literal
                      // before `:id` so it wins the match.
                      GoRoute(
                        path: AppRoutes.newCaseSegment,
                        parentNavigatorKey: rootNavigatorKey,
                        builder: (_, state) => NewCaseScreen(
                          animalId: state.uri.queryParameters['animal'],
                        ),
                      ),
                      // `/cases/browse?…` — transient pre-filtered browser,
                      // full-screen over the shell.
                      GoRoute(
                        path: AppRoutes.casesBrowseSegment,
                        parentNavigatorKey: rootNavigatorKey,
                        builder: (_, state) => CasesScreen(
                          initialQuery: CaseQuery.fromParams(
                            state.uri.queryParameters,
                          ),
                        ),
                      ),
                      // `/cases/:id` — the detail, in the pane navigator: the
                      // right pane on expanded, a full-screen push on compact.
                      GoRoute(
                        path: AppRoutes.detailSegment,
                        builder: (_, state) => CaseDetailScreen(
                          caseId: state.pathParameters['id']!,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            initialLocation: AppRoutes.animals,
            routes: [
              ShellRoute(
                navigatorKey: animalsPaneKey,
                builder: (_, _, child) => ListDetailShell(
                  list: AnimalsScreen(key: animalsListKey),
                  detailChild: child,
                ),
                routes: [
                  GoRoute(
                    path: AppRoutes.animals,
                    builder: (context, _) => context.isExpanded
                        ? DetailPanePlaceholder(
                            icon: Icons.pets_outlined,
                            message: context.l10n.listDetailSelectAnimal,
                          )
                        : AnimalsScreen(key: animalsListKey),
                    routes: [
                      GoRoute(
                        path: AppRoutes.detailSegment,
                        builder: (_, state) => AnimalDetailScreen(
                          animalId: state.pathParameters['id']!,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            initialLocation: AppRoutes.aviaries,
            routes: [
              ShellRoute(
                navigatorKey: aviariesPaneKey,
                builder: (_, _, child) => ListDetailShell(
                  list: AviariesScreen(key: aviariesListKey),
                  detailChild: child,
                ),
                routes: [
                  GoRoute(
                    path: AppRoutes.aviaries,
                    builder: (context, _) => context.isExpanded
                        ? DetailPanePlaceholder(
                            icon: Icons.holiday_village_outlined,
                            message: context.l10n.listDetailSelectAviary,
                          )
                        : AviariesScreen(key: aviariesListKey),
                    routes: [
                      GoRoute(
                        path: AppRoutes.detailSegment,
                        builder: (_, state) => AviaryDetailScreen(
                          aviaryId: state.pathParameters['id']!,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.profile,
        builder: (_, _) => const ProfileScreen(),
      ),
      // Management hub (federfall-zbe): a single full-screen route pushed over
      // the shell. On wide screens [ManagementScreen] lays out the hub and the
      // selected section side-by-side itself (internal selection state) — it is
      // NOT a go_router two-pane, so the hub stays a normal pushed route and
      // its back-to-app affordance never disappears. On narrow screens it
      // pushes the section routes below full-screen. Statistics is reached from
      // the account menu / rail, not the hub.
      GoRoute(
        path: AppRoutes.admin,
        builder: (_, _) => const ManagementScreen(),
      ),
      GoRoute(
        path: AppRoutes.manageTeam,
        builder: (_, _) => const TeamScreen(),
      ),
      GoRoute(
        path: AppRoutes.orgSettings,
        builder: (_, _) => const OrgSettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.conditionsAdmin,
        builder: (_, _) => CodelistAdminScreen(spec: conditionsCodelistSpec),
      ),
      GoRoute(
        path: AppRoutes.admissionReasonsAdmin,
        builder: (_, _) =>
            CodelistAdminScreen(spec: admissionReasonsCodelistSpec),
      ),
      GoRoute(
        path: AppRoutes.markingTypesAdmin,
        builder: (_, _) => CodelistAdminScreen(spec: markingTypesCodelistSpec),
      ),
      GoRoute(
        path: AppRoutes.medicationRoutesAdmin,
        builder: (_, _) =>
            CodelistAdminScreen(spec: medicationRoutesCodelistSpec),
      ),
      GoRoute(
        path: AppRoutes.statistics,
        builder: (_, _) => const StatisticsScreen(),
      ),
      GoRoute(
        path: AppRoutes.today,
        builder: (_, _) => const TodayScreen(),
      ),
      GoRoute(
        path: AppRoutes.confirmReset,
        builder: (_, state) =>
            ConfirmResetScreen(token: state.uri.queryParameters['token']),
      ),
    ],
    errorBuilder: (_, state) => NotFoundScreen(uri: state.uri),
  );
}

/// The gate-only routes (plus the bare root, the old home path): never a
/// destination in their own right once the gate has resolved.
const Set<String> _gatePaths = {
  AppRoutes.splash,
  AppRoutes.login,
  AppRoutes.setup,
  AppRoutes.pending,
  '/',
};

/// Pure redirect decision given the requested [uri] (path + query). Returns
/// the location to send to, or `null` to stay put.
///
/// A deep link that arrives while the gate is unresolved (or unauthenticated)
/// is preserved as a `from` query parameter on the gate routes and restored
/// once the gate lets the user through — so a shared `/cases/abc` link opens
/// that case after sign-in instead of the default landing tab.
String? _gate(Ref ref, Uri uri) {
  final location = uri.path;
  final configAsync = ref.read(serverConfigControllerProvider);

  // Server config not resolved yet → wait on the splash.
  if (!configAsync.hasValue) return _hold(uri, AppRoutes.splash);

  final config = configAsync.requireValue;
  if (config is ServerUnconfigured) return _hold(uri, AppRoutes.setup);

  // Public, no-session route: an invited member setting their password from
  // the email link. Allowed once the server is known (native needs setup
  // first; on web the origin is always resolved).
  if (location == AppRoutes.confirmReset) return null;

  // Configured → gate on auth.
  final authAsync = ref.read(authStatusProvider);
  if (!authAsync.hasValue) return _hold(uri, AppRoutes.splash);

  final authenticated = authAsync.requireValue;
  if (!authenticated) {
    // The login screen adapts to the server's capabilities, so wait until they
    // have resolved before rendering it. serverInfo settles to a value (null on
    // any fetch error), so this only ever pauses on the splash briefly.
    if (ref.read(serverInfoProvider).isLoading) {
      return _hold(uri, AppRoutes.splash);
    }
    return _hold(uri, AppRoutes.login);
  }

  // Authenticated: a self-registered guest has no role yet and is walled off
  // server-side, so keep them on the pending screen until they are promoted.
  final userAsync = ref.read(currentUserProvider);
  if (!userAsync.hasValue) return _hold(uri, AppRoutes.splash);
  final role = userAsync.value?.role;
  if (isGuest(role)) {
    return _hold(uri, AppRoutes.pending);
  }

  // Role-gated surfaces (defense-in-depth; the server access rules are the
  // real boundary and the screens render a lock view): a carer deep-linking
  // to an admin/reporting path is sent home instead of a dead end.
  final isAdminPath = location == AppRoutes.admin ||
      location.startsWith('${AppRoutes.admin}/');
  if (isAdminPath && !canManageTeam(role)) return AppRoutes.home;
  if (location == AppRoutes.statistics && !canViewReports(role)) {
    return AppRoutes.home;
  }

  // Authenticated with a real role: leave the gate for the originally
  // requested location, or the default landing when there is none.
  if (_gatePaths.contains(location)) {
    return _pendingTarget(uri) ?? AppRoutes.home;
  }
  return null;
}

/// Redirects to [gatePath], remembering where the user was actually headed:
/// a non-gate location is stashed in a `from` query parameter, and a hop
/// between gate routes carries the existing one forward. Returns `null` (stay
/// put, keeping any `from`) when already on [gatePath].
String? _hold(Uri uri, String gatePath) {
  if (uri.path == gatePath) return null;
  final from =
      _gatePaths.contains(uri.path) ? _pendingTarget(uri) : uri.toString();
  if (from == null || from == AppRoutes.home) return gatePath;
  return Uri(path: gatePath, queryParameters: {'from': from}).toString();
}

/// The validated `from` parameter of a gate location: the in-app location to
/// restore once the gate resolves. Anything absolute or pointing back at a
/// gate route is discarded (redirect-loop / open-redirect guard).
String? _pendingTarget(Uri uri) {
  final raw = uri.queryParameters['from'];
  if (raw == null || raw.isEmpty) return null;
  final target = Uri.tryParse(raw);
  if (target == null || target.hasScheme || target.hasAuthority) return null;
  if (!target.path.startsWith('/') || _gatePaths.contains(target.path)) {
    return null;
  }
  return raw;
}
