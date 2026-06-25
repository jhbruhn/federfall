import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:federfall/core/server/server_config_controller.dart';
import 'package:federfall/core/server/server_probe.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'connectivity.g.dart';

/// Whether the app can currently reach its backend.
enum OnlineStatus { online, offline }

/// Live online/offline signal for the configured Federfall server.
///
/// "Online" here means *the configured server actually answers* — not merely
/// that the OS has a network interface. A self-hosted server can be down while
/// Wi-Fi is up, so we combine the cheap interface signal from
/// `connectivity_plus` with a real `/api/health` probe via [ServerProbe] — the
/// same reachability check the setup screen uses (and which 7nf.1 will extend
/// with Federfall identity verification). When no server is configured yet
/// (e.g. web before setup) we optimistically report online and let request
/// errors speak.
///
/// Re-checks on every interface change plus a slow heartbeat (so a server that
/// dies under a live connection is still noticed), and only emits on change.
@riverpod
Stream<OnlineStatus> onlineStatus(Ref ref) async* {
  // Read the synchronous dependency before any await: if this provider is
  // disposed during the awaits below, a later `ref.watch` would throw
  // "used after dispose".
  final probe = ref.watch(serverProbeProvider);
  final config = await ref.watch(serverConfigControllerProvider.future);
  final baseUrl = config.baseUrlOrNull;
  final connectivity = Connectivity();

  Future<OnlineStatus> check() async {
    final results = await connectivity.checkConnectivity();
    final interfaceUp = results.any((r) => r != ConnectivityResult.none);
    if (!interfaceUp) return OnlineStatus.offline;
    if (baseUrl == null) return OnlineStatus.online;
    final result = await probe.probe(baseUrl);
    return result is ProbeReachable
        ? OnlineStatus.online
        : OnlineStatus.offline;
  }

  var current = await check();
  if (!ref.mounted) return;
  yield current;

  final controller = StreamController<OnlineStatus>();
  Future<void> reevaluate() async {
    final next = await check();
    if (next != current) {
      current = next;
      controller.add(next);
    }
  }

  final sub = connectivity.onConnectivityChanged.listen(
    (_) => unawaited(reevaluate()),
  );
  final heartbeat = Timer.periodic(
    const Duration(seconds: 30),
    (_) => unawaited(reevaluate()),
  );
  void teardown() {
    unawaited(sub.cancel());
    heartbeat.cancel();
    unawaited(controller.close());
  }

  // Disposed during `await check()` above? Registering onDispose would throw,
  // so tear down inline instead.
  if (!ref.mounted) {
    teardown();
    return;
  }
  ref.onDispose(teardown);

  yield* controller.stream;
}
