import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/core/pocketbase/pocketbase_provider.dart';
import 'package:federfall/core/server/server_config.dart';
import 'package:federfall/core/server/server_config_controller.dart';
import 'package:federfall/core/server/server_info.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'server_info_provider.g.dart';

/// The configured server's identity + capabilities, fetched from the
/// unauthenticated `GET /api/federfall/info` (federfall-7nf.1).
///
/// Null when no server is configured yet, or when the endpoint cannot be
/// reached/parsed — the login screen then falls back to its default option set
/// rather than blocking. Kept alive so the router gate can await it before the
/// login screen renders.
@Riverpod(keepAlive: true)
Future<ServerInfo?> serverInfo(Ref ref) async {
  final config = await ref.watch(serverConfigControllerProvider.future);
  if (config is! ServerConfigured) return null;

  final pb = await ref.watch(pocketBaseProvider.future);
  try {
    // Capped like ServerProbe: the router gate holds unauthenticated users on
    // /splash while this loads, so a black-holed server must fail fast into
    // the null fallback instead of parking them on the spinner for the OS
    // socket timeout.
    final info = await pb
        .send('/api/federfall/info')
        .timeout(const Duration(seconds: 8));
    return ServerInfo.tryParse(info);
  } on Object catch (error, stackTrace) {
    reportCaughtError(error, stackTrace);
    return null;
  }
}
