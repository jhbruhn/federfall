import 'package:federfall/config/app_environment.dart';
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
    this.map,
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
      map: ServerMapConfig.tryParse(json['map']),
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

  /// The map source this server prescribes (federfall-el1f), or null when it
  /// prescribes none — including every server older than that change. Resolve
  /// it through `MapConfig`, which applies the build-time defines as fallback.
  final ServerMapConfig? map;

  @override
  bool operator ==(Object other) =>
      other is ServerInfo &&
      other.version == version &&
      other.minClient == minClient &&
      other.name == name &&
      other.auth == auth &&
      other.map == map;

  @override
  int get hashCode => Object.hash(version, minClient, name, auth, map);
}

/// A complete map source prescribed by the server, from `/info`'s `map` key.
///
/// Exists so a self-hoster can repoint the maps on the published container
/// image, which otherwise only ships whatever tile server was baked into the
/// build as a dart-define (federfall-el1f).
///
/// There is deliberately no partial form: [tryParse] rejects anything that is
/// not a mode plus the URL for *that* mode plus an [attribution], and the
/// server refuses to send one. Half-applied is the shape that does damage —
/// a map serving one provider's tiles under another's credit is a licensing
/// problem, so the credit travels with the URL or neither applies.
@immutable
class ServerMapConfig {
  const ServerMapConfig({
    required this.mode,
    required this.url,
    required this.attribution,
    this.attributionUrl,
    this.apiKey,
  });

  /// Parses the `map` block, returning null unless it is complete and usable —
  /// the caller then keeps the build-time defaults.
  static ServerMapConfig? tryParse(Object? json) {
    if (json is! Map) return null;

    final mode = switch (json['mode']) {
      'raster' => MapMode.raster,
      'vector' => MapMode.vector,
      _ => null,
    };
    if (mode == null) return null;

    // Only the URL belonging to the active mode is read, so a stray key for
    // the other rendering path cannot leak into the wrong one.
    final url =
        (mode == MapMode.raster ? json['tileUrl'] : json['styleUrl'])
            as String? ??
        '';
    // http(s) only: everything downstream feeds this to an image/fetch load,
    // and a scheme we did not expect has no business being handed there.
    if (!url.startsWith('http://') && !url.startsWith('https://')) return null;

    final attribution = json['attribution'] as String? ?? '';
    if (attribution.isEmpty) return null;

    final attributionUrl = json['attributionUrl'] as String?;
    final apiKey = json['apiKey'] as String?;
    return ServerMapConfig(
      mode: mode,
      url: url,
      attribution: attribution,
      // Optional: the visible credit is the licence requirement, the link to a
      // copyright page only the OSMF's recommendation. Absent → plain text,
      // rather than linking a page that describes some other provider.
      attributionUrl: (attributionUrl?.isEmpty ?? true) ? null : attributionUrl,
      apiKey: (apiKey?.isEmpty ?? true) ? null : apiKey,
    );
  }

  /// Which rendering path to use, see [MapMode].
  final MapMode mode;

  /// The MapLibre style JSON URL in [MapMode.vector], or the `{z}/{x}/{y}`
  /// raster template in [MapMode.raster] — one field, because only ever one of
  /// them is in play.
  final String url;

  /// Credit line the map must display for [url]'s provider. Never empty.
  final String attribution;

  /// Copyright/licence page [attribution] links to, or null for plain text.
  final String? attributionUrl;

  /// The tile provider's API key, substituted for the `{key}` token in [url]
  /// and — in [MapMode.vector] — inside the style's own source/sprite/glyph
  /// URLs. Null for a provider that needs none (the shipped default does not).
  ///
  /// `/info` is unauthenticated, so this key is public by construction; the
  /// server-side comment in `info.pb.js` explains why that is nonetheless the
  /// least-bad place for it.
  final String? apiKey;

  @override
  bool operator ==(Object other) =>
      other is ServerMapConfig &&
      other.mode == mode &&
      other.url == url &&
      other.attribution == attribution &&
      other.attributionUrl == attributionUrl &&
      other.apiKey == apiKey;

  @override
  int get hashCode =>
      Object.hash(mode, url, attribution, attributionUrl, apiKey);
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
