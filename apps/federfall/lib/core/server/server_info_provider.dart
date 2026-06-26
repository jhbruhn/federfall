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
    return ServerInfo.tryParse(await pb.send('/api/federfall/info'));
  } on Object {
    return null;
  }
}
