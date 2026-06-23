import 'dart:async';

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

  /// A reachable, healthy Federfall server at [baseUrl] (already normalised).
  const factory ServerProbeResult.reachable(String baseUrl) = ProbeReachable;

  /// The input is not a syntactically valid http(s) URL.
  const factory ServerProbeResult.invalidUrl() = ProbeInvalidUrl;

  /// The address could not be reached (DNS/connection failure or timeout).
  const factory ServerProbeResult.unreachable() = ProbeUnreachable;

  /// Something answered, but it is not a healthy PocketBase/Federfall backend.
  const factory ServerProbeResult.notFederfall() = ProbeNotFederfall;
}

final class ProbeReachable extends ServerProbeResult {
  const ProbeReachable(this.baseUrl);

  final String baseUrl;

  @override
  bool operator ==(Object other) =>
      other is ProbeReachable && other.baseUrl == baseUrl;

  @override
  int get hashCode => baseUrl.hashCode;
}

final class ProbeInvalidUrl extends ServerProbeResult {
  const ProbeInvalidUrl();
}

final class ProbeUnreachable extends ServerProbeResult {
  const ProbeUnreachable();
}

final class ProbeNotFederfall extends ServerProbeResult {
  const ProbeNotFederfall();
}

/// Hits a server's `GET /api/health` and returns the parsed health DTO. Pulled
/// out behind a typedef so tests can supply a fake without real networking.
typedef HealthProber = Future<HealthCheck> Function(String baseUrl);

Future<HealthCheck> _defaultProber(String baseUrl) =>
    PocketBase(baseUrl).health.check().timeout(const Duration(seconds: 8));

/// Validates a candidate server address before it is persisted (FED-3.0):
/// normalise → probe `/api/health` → classify the outcome.
class ServerProbe {
  const ServerProbe([this._prober = _defaultProber]);

  final HealthProber _prober;

  Future<ServerProbeResult> probe(String input) async {
    final normalized = normalizeServerUrl(input);
    if (normalized == null) return const ServerProbeResult.invalidUrl();

    try {
      final health = await _prober(normalized);
      // PocketBase answers a healthy check with code 200; anything else means
      // we reached *something* that is not a Federfall backend.
      return health.code == 200
          ? ServerProbeResult.reachable(normalized)
          : const ServerProbeResult.notFederfall();
    } on ClientException catch (e) {
      // statusCode 0 == no HTTP response at all (connection refused, DNS,
      // abort); a real status code means it answered but unhealthily.
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
