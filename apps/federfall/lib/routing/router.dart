import 'package:federfall/core/auth/auth_status.dart';
import 'package:federfall/core/server/server_config.dart';
import 'package:federfall/core/server/server_config_controller.dart';
import 'package:federfall/features/auth/login_screen.dart';
import 'package:federfall/features/cases/case_detail_screen.dart';
import 'package:federfall/features/cases/new_case_screen.dart';
import 'package:federfall/features/home/home_screen.dart';
import 'package:federfall/features/server_setup/setup_screen.dart';
import 'package:federfall/features/startup/splash_screen.dart';
import 'package:federfall/routing/app_routes.dart';
import 'package:federfall/routing/not_found_screen.dart';
import 'package:flutter/foundation.dart';
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

  return GoRouter(
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
        path: AppRoutes.home,
        builder: (_, _) => const HomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.newCase,
        builder: (_, _) => const NewCaseScreen(),
      ),
      GoRoute(
        path: AppRoutes.caseDetailPattern,
        builder: (_, state) =>
            CaseDetailScreen(caseId: state.pathParameters['id']!),
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

  // Configured → gate on auth.
  final authAsync = ref.read(authStatusProvider);
  if (!authAsync.hasValue) {
    return location == AppRoutes.splash ? null : AppRoutes.splash;
  }

  final authenticated = authAsync.requireValue;
  if (!authenticated) {
    return location == AppRoutes.login ? null : AppRoutes.login;
  }

  // Authenticated: bounce away from the gate-only routes.
  const gateRoutes = {AppRoutes.splash, AppRoutes.login, AppRoutes.setup};
  return gateRoutes.contains(location) ? AppRoutes.home : null;
}
