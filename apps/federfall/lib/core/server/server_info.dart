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
    this.oauth2Scopes = const {},
    this.passwordReset = false,
    this.selfSignup = false,
  });

  factory ServerAuthOptions.fromJson(Map<Object?, Object?> json) {
    final providers = json['oauth2'];
    final scopes = json['oauth2Scopes'];
    return ServerAuthOptions(
      password: json['password'] as bool? ?? true,
      oauth2: providers is List
          ? providers.whereType<String>().toList(growable: false)
          : const [],
      oauth2Scopes: scopes is Map
          ? {
              for (final entry in scopes.entries)
                if (entry.key is String && entry.value is List)
                  entry.key! as String: (entry.value! as List)
                      .whereType<String>()
                      .toList(growable: false),
            }
          : const {},
      passwordReset: json['passwordReset'] as bool? ?? false,
      selfSignup: json['selfSignup'] as bool? ?? false,
    );
  }

  /// Email + password sign-in is available.
  final bool password;

  /// Names of enabled OAuth2 providers (empty when none).
  final List<String> oauth2;

  /// The OAuth2 scopes the app should request, per provider name
  /// (federfall-lnz3).
  ///
  /// PocketBase hardcodes a minimal scope set and offers no server-side way to
  /// widen it — upstream treats scopes as the client's business, since the
  /// client is what opens the authorization URL. So the server prescribes them
  /// here and the sign-in paths apply them, REPLACING the `scope` parameter
  /// PocketBase built (that is also what the SDK's own `scopes` option does),
  /// which is why a configured list has to be complete rather than additive.
  ///
  /// In practice the server sends this for a generic OIDC provider once a
  /// group-to-role mapping is configured, because the groups claim is only
  /// released to a request that asked for the matching scope. A provider
  /// missing from the map — the default, and everything an older server sends
  /// — keeps PocketBase's own scopes untouched.
  final Map<String, List<String>> oauth2Scopes;

  /// The server can send password-reset email (SMTP configured).
  final bool passwordReset;

  /// Self-registration is open (false for invite-only Federfall instances).
  final bool selfSignup;

  @override
  bool operator ==(Object other) =>
      other is ServerAuthOptions &&
      other.password == password &&
      listEquals(other.oauth2, oauth2) &&
      _sameScopes(other.oauth2Scopes, oauth2Scopes) &&
      other.passwordReset == passwordReset &&
      other.selfSignup == selfSignup;

  @override
  int get hashCode => Object.hash(
    password,
    Object.hashAll(oauth2),
    // Unordered: the map comes from JSON, whose key order is incidental.
    Object.hashAllUnordered([
      for (final entry in oauth2Scopes.entries)
        Object.hash(entry.key, Object.hashAll(entry.value)),
    ]),
    passwordReset,
    selfSignup,
  );

  /// Deep equality for the scope map — `mapEquals` would compare the [List]
  /// values by identity, so two equal parses would come out different.
  static bool _sameScopes(
    Map<String, List<String>> a,
    Map<String, List<String>> b,
  ) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      final other = b[entry.key];
      if (other == null || !listEquals(other, entry.value)) return false;
    }
    return true;
  }
}
