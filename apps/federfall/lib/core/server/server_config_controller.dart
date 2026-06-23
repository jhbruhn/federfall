import 'package:federfall/config/app_environment.dart';
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
///   * **native** — the persisted URL, or [ServerUnconfigured] when unset (a
///     build-time override seeds it for dev).
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

    if (AppEnvironment.hasPocketbaseUrlOverride) {
      return const ServerConfig.configured(
        AppEnvironment.pocketbaseUrlOverride,
      );
    }

    return const ServerConfig.unconfigured();
  }

  /// Persists [url] as the active native server and switches to it.
  Future<void> setServerUrl(String url) async {
    await ref.read(serverUrlStorageProvider).write(url);
    state = AsyncData(ServerConfig.configured(url));
  }

  /// Forgets the native server URL, returning to the setup gate.
  Future<void> clearServerUrl() async {
    await ref.read(serverUrlStorageProvider).delete();
    state = const AsyncData(ServerConfig.unconfigured());
  }

  /// On web the app and backend share an origin; a build-time override (used in
  /// dev where they run on different ports) takes precedence.
  String _webBaseUrl() => AppEnvironment.hasPocketbaseUrlOverride
      ? AppEnvironment.pocketbaseUrlOverride
      : Uri.base.origin;
}
