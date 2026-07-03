import 'dart:async';

import 'package:federfall/core/pocketbase/user_agent_client.dart';
import 'package:federfall/core/server/server_info.dart';
import 'package:flutter/foundation.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'server_probe.g.dart';

/// Normalises a user-entered server address into a canonical base URL, or
/// returns `null` when the input cannot be a valid http(s) URL.
///
/// Rules: trim; assume `https://` when no scheme is given (so `pigeons.example`
/// and `192.168.1.5:8090` work); accept only http/https; require a host; drop
/// any query/fragment and trailing slashes while preserving an explicit port
/// and sub-path (some self-hosters run PocketBase under a path).
String? normalizeServerUrl(String input) {
  var raw = input.trim();
  if (raw.isEmpty) return null;
  if (!raw.contains('://')) raw = 'https://$raw';

  final uri = Uri.tryParse(raw);
  if (uri == null ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty) {
    return null;
  }

  var path = uri.path;
  while (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }

  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: path,
  ).toString();
}

/// Outcome of probing a candidate server address (FED-3.0).
@immutable
sealed class ServerProbeResult {
  const ServerProbeResult();

  /// A verified Federfall server at [baseUrl] (already normalised), with the
  /// capabilities it reported.
  const factory ServerProbeResult.reachable(
    String baseUrl,
    ServerInfo info,
  ) = ProbeReachable;

  /// The input is not a syntactically valid http(s) URL.
  const factory ServerProbeResult.invalidUrl() = ProbeInvalidUrl;

  /// An explicit `http://` scheme was given for a non-loopback host, which
  /// would send the bearer token in cleartext. Rejected before probing.
  const factory ServerProbeResult.insecureHttp() = ProbeInsecureHttp;

  /// The address could not be reached (DNS/connection failure or timeout).
  const factory ServerProbeResult.unreachable() = ProbeUnreachable;

  /// Something answered, but it is not a Federfall backend (no identity marker
  /// — e.g. a generic PocketBase, or an unrelated host returning a 200).
  const factory ServerProbeResult.notFederfall() = ProbeNotFederfall;
}

final class ProbeReachable extends ServerProbeResult {
  const ProbeReachable(this.baseUrl, this.info);

  final String baseUrl;

  /// The server's reported identity + capabilities.
  final ServerInfo info;

  @override
  bool operator ==(Object other) =>
      other is ProbeReachable && other.baseUrl == baseUrl && other.info == info;

  @override
  int get hashCode => Object.hash(baseUrl, info);
}

final class ProbeInvalidUrl extends ServerProbeResult {
  const ProbeInvalidUrl();
}

final class ProbeInsecureHttp extends ServerProbeResult {
  const ProbeInsecureHttp();
}

final class ProbeUnreachable extends ServerProbeResult {
  const ProbeUnreachable();
}

final class ProbeNotFederfall extends ServerProbeResult {
  const ProbeNotFederfall();
}

/// Fetches a server's `GET /api/federfall/info` and returns the decoded JSON
/// body. Pulled out behind a typedef so tests can supply a fake without real
/// networking.
typedef ServerInfoProber = Future<Object?> Function(String baseUrl);

Future<Object?> _defaultProber(String baseUrl) async {
  final ua = await loadUserAgent();
  return PocketBase(
    baseUrl,
    httpClientFactory: () => UserAgentClient(ua),
  ).send('/api/federfall/info').timeout(const Duration(seconds: 8));
}

/// Validates a candidate server address before it is persisted (FED-3.0,
/// federfall-7nf.1): normalise → fetch `/api/federfall/info` → require the
/// Federfall identity marker → classify the outcome. A generic PocketBase has
/// no such route (404) and is rejected as not-Federfall.
class ServerProbe {
  const ServerProbe([this._prober = _defaultProber]);

  final ServerInfoProber _prober;

  Future<ServerProbeResult> probe(String input) async {
    final normalized = normalizeServerUrl(input);
    if (normalized == null) return const ServerProbeResult.invalidUrl();

    // http:// sends the bearer token in cleartext. The OS already blocks it
    // in release builds (no usesCleartextTraffic/ATS exception), which just
    // surfaces as an opaque connection failure — reject it here instead with
    // a clear reason. Loopback stays allowed as the local-dev escape hatch
    // (the development flavor points at http://localhost:8090).
    final uri = Uri.parse(normalized);
    final host = uri.host.toLowerCase();
    final isLoopback =
        host == 'localhost' || host == '127.0.0.1' || host == '::1';
    if (uri.scheme == 'http' && !isLoopback) {
      return const ServerProbeResult.insecureHttp();
    }

    try {
      final info = ServerInfo.tryParse(await _prober(normalized));
      // Something answered, but without the Federfall marker it is not our
      // backend (a bare PocketBase, a reverse proxy, an unrelated 200, ...).
      return info == null
          ? const ServerProbeResult.notFederfall()
          : ServerProbeResult.reachable(normalized, info);
    } on ClientException catch (e) {
      // statusCode 0 == no HTTP response at all (connection refused, DNS,
      // abort); any real status (e.g. a 404 for the missing route on a generic
      // PocketBase) means it answered but is not Federfall.
      return e.statusCode == 0
          ? const ServerProbeResult.unreachable()
          : const ServerProbeResult.notFederfall();
    } on TimeoutException {
      return const ServerProbeResult.unreachable();
    }
  }
}

@riverpod
ServerProbe serverProbe(Ref ref) => const ServerProbe();
