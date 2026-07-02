import 'package:federfall/config/app_environment.dart';
import 'package:federfall/core/pocketbase/auth_token_storage.dart';
import 'package:federfall/core/server/server_config.dart';
import 'package:federfall/core/server/server_url_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'server_config_controller.g.dart';

/// Resolves and owns the [ServerConfig] for the running app, and lets the
/// native setup flow (FED-3.0) change it.
///
/// Resolution rules:
///   * **web** — always configured; the base URL is the app's serving origin
///     (`Uri.base.origin`), since backend and frontend share the domain. A
///     build-time `POCKETBASE_URL` override wins (dev convenience).
///   * **native** — the persisted URL, or [ServerUnconfigured] when unset, so
///     first run always lands on the setup screen. The build-time
///     `POCKETBASE_URL` override never auto-configures here (that would skip
///     setup); it only *prefills* the setup field for dev — see `SetupScreen`.
///
/// Mutating the URL replaces the state, which transitively rebuilds the
/// PocketBase client (it is keyed on this config).
@Riverpod(keepAlive: true)
class ServerConfigController extends _$ServerConfigController {
  @override
  Future<ServerConfig> build() async {
    if (kIsWeb) {
      return ServerConfig.configured(_webBaseUrl());
    }

    final stored = await ref.watch(serverUrlStorageProvider).read();
    if (stored != null && stored.isNotEmpty) {
      return ServerConfig.configured(stored);
    }

    return const ServerConfig.unconfigured();
  }

  /// Persists [url] as the active native server and switches to it.
  ///
  /// A persisted auth payload belongs to the origin it was issued by, so it is
  /// purged whenever the URL actually changes — otherwise the rebuilt
  /// PocketBase client would send the previous server's bearer token to the
  /// new (potentially untrusted) host.
  Future<void> setServerUrl(String url) async {
    final urlStorage = ref.read(serverUrlStorageProvider);
    final previous = await urlStorage.read();
    if (previous != url) {
      await ref.read(authTokenStorageProvider).delete();
    }
    await urlStorage.write(url);
    state = AsyncData(ServerConfig.configured(url));
  }

  /// Forgets the native server URL, returning to the setup gate. The persisted
  /// auth payload goes with it (see [setServerUrl]).
  Future<void> clearServerUrl() async {
    await ref.read(serverUrlStorageProvider).delete();
    await ref.read(authTokenStorageProvider).delete();
    state = const AsyncData(ServerConfig.unconfigured());
  }

  /// On web the app and backend share an origin; a build-time override (used in
  /// dev where they run on different ports) takes precedence.
  String _webBaseUrl() => AppEnvironment.hasPocketbaseUrlOverride
      ? AppEnvironment.pocketbaseUrlOverride
      : Uri.base.origin;
}
