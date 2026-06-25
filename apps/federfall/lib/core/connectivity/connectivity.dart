import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:federfall/core/server/server_config_controller.dart';
import 'package:federfall/core/server/server_probe.dart';
import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'connectivity.g.dart';

/// Whether the app can currently reach its backend.
enum OnlineStatus { online, offline }

/// How long to wait before re-probing after a failed check.
const _retryGap = Duration(seconds: 1);

/// Total number of probe attempts before trusting an `offline` reading.
const _offlineConfirmAttempts = 2;

/// Confirms an `offline` reading before trusting it.
///
/// A single failed probe is treated as tentative — right after the app resumes
/// the network interface may still be waking up, or the `/health` probe may
/// time out transiently — so latching `offline` on one failure produces a
/// spurious banner (federfall-vcm). Returns as soon as any probe reports
/// `online`; only commits to `offline` after [attempts] consecutive failures
/// spaced by [gap]. Bails out early if [isMounted] returns false during a gap.
Future<OnlineStatus> confirmStatus(
  Future<OnlineStatus> Function() probeOnce, {
  int attempts = _offlineConfirmAttempts,
  Duration gap = _retryGap,
  bool Function()? isMounted,
}) async {
  var status = await probeOnce();
  var remaining = attempts - 1;
  while (status == OnlineStatus.offline && remaining > 0) {
    await Future<void>.delayed(gap);
    if (isMounted != null && !isMounted()) return status;
    status = await probeOnce();
    remaining--;
  }
  return status;
}

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
/// Re-checks on every interface change, on app lifecycle resume (so returning
/// from background re-probes promptly instead of waiting for an interface
/// change that may never come), plus a slow heartbeat (so a server that dies
/// under a live connection is still noticed), and only emits on change.
@riverpod
Stream<OnlineStatus> onlineStatus(Ref ref) async* {
  // Read the synchronous dependency before any await: if this provider is
  // disposed during the awaits below, a later `ref.watch` would throw
  // "used after dispose".
  final probe = ref.watch(serverProbeProvider);
  final config = await ref.watch(serverConfigControllerProvider.future);
  final baseUrl = config.baseUrlOrNull;
  final connectivity = Connectivity();

  Future<OnlineStatus> probeOnce() async {
    final results = await connectivity.checkConnectivity();
    final interfaceUp = results.any((r) => r != ConnectivityResult.none);
    if (!interfaceUp) return OnlineStatus.offline;
    if (baseUrl == null) return OnlineStatus.online;
    final result = await probe.probe(baseUrl);
    return result is ProbeReachable
        ? OnlineStatus.online
        : OnlineStatus.offline;
  }

  // De-flap: a single failed probe is tentative, so a transient blip (notably
  // right after resume) does not latch a spurious offline banner.
  Future<OnlineStatus> check() =>
      confirmStatus(probeOnce, isMounted: () => ref.mounted);

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
  // Returning from background may not emit an interface change, so re-probe on
  // resume to clear a stale offline reading promptly (federfall-vcm).
  final lifecycle = AppLifecycleListener(
    onResume: () => unawaited(reevaluate()),
  );
  void teardown() {
    unawaited(sub.cancel());
    heartbeat.cancel();
    lifecycle.dispose();
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
