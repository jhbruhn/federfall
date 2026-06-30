import 'package:federfall/core/auth/auth_status.dart';
import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/auth/roles.dart';
import 'package:federfall/core/server/server_config.dart';
import 'package:federfall/core/server/server_config_controller.dart';
import 'package:federfall/core/server/server_info_provider.dart';
import 'package:federfall/features/admin/admission_reasons_admin_screen.dart';
import 'package:federfall/features/admin/conditions_admin_screen.dart';
import 'package:federfall/features/admin/management_screen.dart';
import 'package:federfall/features/admin/marking_types_admin_screen.dart';
import 'package:federfall/features/admin/medication_routes_admin_screen.dart';
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

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: AppRoutes.home,
    refreshListenable: refresh,
    redirect: (context, state) => _gate(ref, state.matchedLocation),
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
                  list: const CasesScreen(),
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
                        : const CasesScreen(),
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
                  list: const AnimalsScreen(),
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
                        : const AnimalsScreen(),
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
                  list: const AviariesScreen(),
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
                        : const AviariesScreen(),
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
        builder: (_, _) => const ConditionsAdminScreen(),
      ),
      GoRoute(
        path: AppRoutes.admissionReasonsAdmin,
        builder: (_, _) => const AdmissionReasonsAdminScreen(),
      ),
      GoRoute(
        path: AppRoutes.markingTypesAdmin,
        builder: (_, _) => const MarkingTypesAdminScreen(),
      ),
      GoRoute(
        path: AppRoutes.medicationRoutesAdmin,
        builder: (_, _) => const MedicationRoutesAdminScreen(),
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

/// Pure redirect decision given the current location. Returns the path to send
/// to, or `null` to stay put.
String? _gate(Ref ref, String location) {
  final configAsync = ref.read(serverConfigControllerProvider);

  // Server config not resolved yet → wait on the splash.
  if (!configAsync.hasValue) {
    return location == AppRoutes.splash ? null : AppRoutes.splash;
  }

  final config = configAsync.requireValue;
  if (config is ServerUnconfigured) {
    return location == AppRoutes.setup ? null : AppRoutes.setup;
  }

  // Public, no-session route: an invited member setting their password from
  // the email link. Allowed once the server is known (native needs setup
  // first; on web the origin is always resolved).
  if (location == AppRoutes.confirmReset) return null;

  // Configured → gate on auth.
  final authAsync = ref.read(authStatusProvider);
  if (!authAsync.hasValue) {
    return location == AppRoutes.splash ? null : AppRoutes.splash;
  }

  final authenticated = authAsync.requireValue;
  if (!authenticated) {
    // The login screen adapts to the server's capabilities, so wait until they
    // have resolved before rendering it. serverInfo settles to a value (null on
    // any fetch error), so this only ever pauses on the splash briefly.
    if (ref.read(serverInfoProvider).isLoading) {
      return location == AppRoutes.splash ? null : AppRoutes.splash;
    }
    return location == AppRoutes.login ? null : AppRoutes.login;
  }

  // Authenticated: a self-registered guest has no role yet and is walled off
  // server-side, so keep them on the pending screen until they are promoted.
  final userAsync = ref.read(currentUserProvider);
  if (!userAsync.hasValue) {
    return location == AppRoutes.splash ? null : AppRoutes.splash;
  }
  if (isGuest(userAsync.value?.role)) {
    return location == AppRoutes.pending ? null : AppRoutes.pending;
  }

  // Authenticated with a real role: bounce away from the gate-only routes and
  // the bare root (the old home path, now unmatched) onto the default landing.
  const gateRoutes = {
    AppRoutes.splash,
    AppRoutes.login,
    AppRoutes.setup,
    AppRoutes.pending,
    '/',
  };
  return gateRoutes.contains(location) ? AppRoutes.home : null;
}
