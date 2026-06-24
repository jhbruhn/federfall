import 'package:federfall/core/auth/auth_status.dart';
import 'package:federfall/core/server/server_config.dart';
import 'package:federfall/core/server/server_config_controller.dart';
import 'package:federfall/features/admin/admin_screen.dart';
import 'package:federfall/features/animals/animal_detail_screen.dart';
import 'package:federfall/features/animals/animals_screen.dart';
import 'package:federfall/features/auth/confirm_reset_screen.dart';
import 'package:federfall/features/auth/login_screen.dart';
import 'package:federfall/features/aviaries/aviaries_screen.dart';
import 'package:federfall/features/cases/case_detail_screen.dart';
import 'package:federfall/features/cases/cases_screen.dart';
import 'package:federfall/features/cases/new_case_screen.dart';
import 'package:federfall/features/dashboard/dashboard_screen.dart';
import 'package:federfall/features/home/nav_shell.dart';
import 'package:federfall/features/profile/profile_screen.dart';
import 'package:federfall/features/server_setup/setup_screen.dart';
import 'package:federfall/features/startup/splash_screen.dart';
import 'package:federfall/features/statistics/statistics_screen.dart';
import 'package:federfall/routing/app_routes.dart';
import 'package:federfall/routing/not_found_screen.dart';
import 'package:flutter/widgets.dart';
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
    ..listen(authStatusProvider, (_, _) => refresh.value++)
    ..onDispose(refresh.dispose);

  // Detail/create routes nest under their shell branch but render full-screen
  // over the shell by living on the root navigator.
  final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

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
            routes: [
              GoRoute(
                path: AppRoutes.cases,
                builder: (_, _) => const CasesScreen(),
                routes: [
                  // `/cases/new` — declared before `:id` so the literal wins.
                  GoRoute(
                    path: AppRoutes.newCaseSegment,
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (_, _) => const NewCaseScreen(),
                  ),
                  GoRoute(
                    path: AppRoutes.detailSegment,
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (_, state) =>
                        CaseDetailScreen(caseId: state.pathParameters['id']!),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.animals,
                builder: (_, _) => const AnimalsScreen(),
                routes: [
                  GoRoute(
                    path: AppRoutes.detailSegment,
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (_, state) => AnimalDetailScreen(
                      animalId: state.pathParameters['id']!,
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.aviaries,
                builder: (_, _) => const AviariesScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.profile,
        builder: (_, _) => const ProfileScreen(),
      ),
      GoRoute(
        path: AppRoutes.admin,
        builder: (_, _) => const AdminScreen(),
      ),
      GoRoute(
        path: AppRoutes.statistics,
        builder: (_, _) => const StatisticsScreen(),
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
    return location == AppRoutes.login ? null : AppRoutes.login;
  }

  // Authenticated: bounce away from the gate-only routes and the bare root
  // (the old home path, now unmatched) onto the default landing destination.
  const gateRoutes = {AppRoutes.splash, AppRoutes.login, AppRoutes.setup, '/'};
  return gateRoutes.contains(location) ? AppRoutes.home : null;
}
