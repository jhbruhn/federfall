import 'dart:async';

import 'package:federfall/core/server/server_config.dart';
import 'package:federfall/core/server/server_config_controller.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'session_refresh.g.dart';

/// How often to proactively roll the session token while the app stays open.
///
/// The server token lives 30 days (see the `..._users_auth_token_duration`
/// migration); refreshing far more often than that keeps a continuously-used
/// session alive indefinitely without being chatty. Foregrounded desktop/web
/// sessions rely on this — they never fire [AppLifecycleListener.onResume]; on
/// mobile, resume already covers the common background-then-return case.
const _heartbeat = Duration(hours: 6);

/// Silently rolls the PocketBase session token so active users are not logged
/// out when it expires.
///
/// PocketBase issues its own JWT (for OIDC/OAuth2 logins too — the provider's
/// tokens are not used to extend the session) and the client stores it with a
/// fixed `exp`. Without this, the token simply lapsed after its duration and
/// the router gate bounced the user to `/login`. Here we call
/// [AuthRepository.refresh] — which re-issues a token with a fresh `exp` — once
/// at startup, whenever the app resumes from background, and on a slow
/// heartbeat, so every active use rolls the window forward.
///
/// [AuthRepository.refresh] is a no-op when signed out (the store is invalid)
/// and clears the store only on a 401/403 (a genuinely dead/revoked token). A
/// refresh that fails for any other reason (offline, server down) is swallowed:
/// a transient network blip must never log the user out.
///
/// Kept alive and activated by the router, which listens to it at startup.
@Riverpod(keepAlive: true)
Future<void> sessionRefresh(Ref ref) async {
  // Until a server is configured there is no client to refresh against — and
  // resolving the repo would force PocketBase to initialise without a URL and
  // fault. Bail out now; this rebuilds (and wires up) once setup completes.
  final config = await ref.watch(serverConfigControllerProvider.future);
  if (config is! ServerConfigured) return;

  final repo = await ref.watch(authRepositoryProvider.future);

  Future<void> refresh() async {
    try {
      await repo.refresh();
    } on Object {
      // Offline / server down / any non-401-403 failure: leave the session
      // untouched. refresh() itself clears the store on a genuinely dead token.
    }
  }

  final lifecycle = AppLifecycleListener(onResume: () => unawaited(refresh()));
  final heartbeat = Timer.periodic(_heartbeat, (_) => unawaited(refresh()));
  void teardown() {
    lifecycle.dispose();
    heartbeat.cancel();
  }

  // Disposed during the await above? Registering onDispose would throw, so tear
  // down inline instead.
  if (!ref.mounted) {
    teardown();
    return;
  }
  ref.onDispose(teardown);

  // Roll the window (and validate against the server) once at startup.
  unawaited(refresh());
}
