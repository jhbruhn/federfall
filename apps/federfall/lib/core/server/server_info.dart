import 'package:flutter/foundation.dart';

/// Identity + capabilities of a Federfall backend, as returned by the
/// unauthenticated `GET /api/federfall/info` endpoint (federfall-7nf.1).
///
/// Used in two places: `ServerProbe` requires a parseable instance (with the
/// federfall marker) before it accepts a server URL, and the login screen reads
/// [auth] to show only the options the server actually offers.
@immutable
class ServerInfo {
  const ServerInfo({
    required this.version,
    required this.name,
    required this.auth,
    this.minClient,
  });

  /// Parses an `/api/federfall/info` body, returning null when [json] is not a
  /// recognisable Federfall payload (missing marker / wrong shape) — that is
  /// how a generic PocketBase or unrelated 200 is rejected.
  static ServerInfo? tryParse(Object? json) {
    if (json is! Map) return null;
    final marker = json['federfall'] == true || json['service'] == 'federfall';
    if (!marker) return null;

    final authJson = json['auth'];
    return ServerInfo(
      version: json['version'] as String? ?? '',
      minClient: json['minClient'] as String?,
      name: json['name'] as String? ?? 'Federfall',
      auth: ServerAuthOptions.fromJson(authJson is Map ? authJson : const {}),
    );
  }

  /// Server/schema version, for display and diagnostics.
  final String version;

  /// Oldest client build this server supports, or null when unspecified.
  final String? minClient;

  /// Branding/instance name shown on the login screen.
  final String name;

  /// Which auth methods the server offers.
  final ServerAuthOptions auth;

  @override
  bool operator ==(Object other) =>
      other is ServerInfo &&
      other.version == version &&
      other.minClient == minClient &&
      other.name == name &&
      other.auth == auth;

  @override
  int get hashCode => Object.hash(version, minClient, name, auth);
}

/// The auth methods a Federfall server has enabled.
@immutable
class ServerAuthOptions {
  const ServerAuthOptions({
    this.password = true,
    this.oauth2 = const [],
    this.passwordReset = false,
    this.selfSignup = false,
  });

  factory ServerAuthOptions.fromJson(Map<Object?, Object?> json) {
    final providers = json['oauth2'];
    return ServerAuthOptions(
      password: json['password'] as bool? ?? true,
      oauth2: providers is List
          ? providers.whereType<String>().toList(growable: false)
          : const [],
      passwordReset: json['passwordReset'] as bool? ?? false,
      selfSignup: json['selfSignup'] as bool? ?? false,
    );
  }

  /// Email + password sign-in is available.
  final bool password;

  /// Names of enabled OAuth2 providers (empty when none).
  final List<String> oauth2;

  /// The server can send password-reset email (SMTP configured).
  final bool passwordReset;

  /// Self-registration is open (false for invite-only Federfall instances).
  final bool selfSignup;

  @override
  bool operator ==(Object other) =>
      other is ServerAuthOptions &&
      other.password == password &&
      listEquals(other.oauth2, oauth2) &&
      other.passwordReset == passwordReset &&
      other.selfSignup == selfSignup;

  @override
  int get hashCode =>
      Object.hash(password, Object.hashAll(oauth2), passwordReset, selfSignup);
}
