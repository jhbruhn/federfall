import 'package:flutter/foundation.dart';

/// The resolved backend location for the running app.
///
/// On web the server is always "configured" — the app is served from the same
/// origin as PocketBase, so the base URL is the serving origin. On native the
/// user must enter and persist a server URL (FED-3.0); until they do the config
/// is [ServerUnconfigured] and routing redirects to the setup screen.
@immutable
sealed class ServerConfig {
  const ServerConfig();

  const factory ServerConfig.configured(String baseUrl) = ServerConfigured;

  const factory ServerConfig.unconfigured() = ServerUnconfigured;

  /// The resolved base URL, or `null` when not yet configured.
  String? get baseUrlOrNull => switch (this) {
        ServerConfigured(:final baseUrl) => baseUrl,
        ServerUnconfigured() => null,
      };
}

/// A resolved server: requests go to [baseUrl].
final class ServerConfigured extends ServerConfig {
  const ServerConfigured(this.baseUrl);

  final String baseUrl;

  @override
  bool operator ==(Object other) =>
      other is ServerConfigured && other.baseUrl == baseUrl;

  @override
  int get hashCode => baseUrl.hashCode;

  @override
  String toString() => 'ServerConfigured($baseUrl)';
}

/// Native-only: no server URL has been entered yet.
final class ServerUnconfigured extends ServerConfig {
  const ServerUnconfigured();

  @override
  bool operator ==(Object other) => other is ServerUnconfigured;

  @override
  int get hashCode => 0;

  @override
  String toString() => 'ServerUnconfigured()';
}
