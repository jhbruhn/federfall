import 'package:federfall/core/pocketbase/pocketbase_provider.dart';
import 'package:federfall/core/server/server_config.dart';
import 'package:federfall/core/server/server_config_controller.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'auth_status.g.dart';

/// Whether there is a currently valid (non-expired) PocketBase session.
///
/// This is the minimal signal the router's redirect gate needs (FED-2.4). The
/// full login/session lifecycle — sign in, sign out, refresh — lands in
/// FED-3.1 and will drive the same auth store this watches.
///
/// Returns `false` (rather than erroring) when no server is configured yet, so
/// the gate can send native users to the setup screen first.
@Riverpod(keepAlive: true)
class AuthStatus extends _$AuthStatus {
  @override
  Future<bool> build() async {
    final config = await ref.watch(serverConfigControllerProvider.future);
    if (config is! ServerConfigured) return false;

    final pb = await ref.watch(pocketBaseProvider.future);

    // Re-evaluate whenever the session changes (login/logout/refresh).
    final sub = pb.authStore.onChange.listen((_) => ref.invalidateSelf());
    // Disposed during the awaits above? onDispose would throw; cancel inline.
    if (!ref.mounted) {
      await sub.cancel();
      return pb.authStore.isValid;
    }
    ref.onDispose(sub.cancel);

    return pb.authStore.isValid;
  }
}
