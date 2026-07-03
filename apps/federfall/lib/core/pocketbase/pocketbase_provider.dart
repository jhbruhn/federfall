import 'package:federfall/core/pocketbase/auth_token_storage.dart';
import 'package:federfall/core/pocketbase/user_agent_client.dart';
import 'package:federfall/core/server/server_config.dart';
import 'package:federfall/core/server/server_config_controller.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'pocketbase_provider.g.dart';

/// Thrown when the PocketBase client is requested on native before a server URL
/// has been configured. Routing gates on [ServerConfigController] so this
/// should only surface as a programming error.
class ServerNotConfiguredException implements Exception {
  const ServerNotConfiguredException();

  @override
  String toString() => 'ServerNotConfiguredException: no server URL configured';
}

/// The app-wide [PocketBase] client.
///
/// Built asynchronously because restoring a session requires reading the
/// persisted auth payload first; that initial value seeds an [AsyncAuthStore]
/// whose `save`/`clear` write back through [AuthTokenStorage]. The provider is
/// keyed on [ServerConfigController], so switching servers (native) rebuilds a
/// fresh client pointed at the new origin with a clean auth store.
@Riverpod(keepAlive: true)
Future<PocketBase> pocketBase(Ref ref) async {
  final config = await ref.watch(serverConfigControllerProvider.future);
  final baseUrl = switch (config) {
    ServerConfigured(:final baseUrl) => baseUrl,
    ServerUnconfigured() => throw const ServerNotConfiguredException(),
  };

  final storage = ref.watch(authTokenStorageProvider);
  final initial = await storage.read();
  final ua = await ref.watch(userAgentProvider.future);

  final authStore = AsyncAuthStore(
    save: storage.write,
    clear: storage.delete,
    initial: initial,
  );

  return PocketBase(
    baseUrl,
    authStore: authStore,
    httpClientFactory: () => UserAgentClient(ua),
  );
}
