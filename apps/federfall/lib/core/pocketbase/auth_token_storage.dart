import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'auth_token_storage.g.dart';

/// Persistence for the encoded PocketBase auth payload (token + record JSON).
///
/// The payload is what `AsyncAuthStore` hands us in its `save` callback. It is
/// sensitive (a bearer token), so on native it lives in the platform keychain /
/// keystore via `flutter_secure_storage`. On web there is no real secure
/// storage, so we fall back to `shared_preferences` (localStorage) — the same
/// place the official PocketBase JS SDK keeps it.
abstract interface class AuthTokenStorage {
  /// Reads the stored auth payload, or `null` if none.
  Future<String?> read();

  /// Persists the encoded auth payload.
  Future<void> write(String data);

  /// Clears any stored auth payload.
  Future<void> delete();
}

/// Native implementation backed by the platform keychain/keystore.
class SecureAuthTokenStorage implements AuthTokenStorage {
  SecureAuthTokenStorage([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'federfall.auth';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String data) => _storage.write(key: _key, value: data);

  @override
  Future<void> delete() => _storage.delete(key: _key);
}

/// Web fallback backed by `shared_preferences` (localStorage).
///
/// This is a conscious, documented tradeoff (federfall-xe9), not an
/// oversight: no browser API gives a Flutter web app real secure storage
/// (no keychain-equivalent), so the token sits in localStorage, readable by
/// any script that runs in this origin — an XSS bug here would be a full
/// account takeover. The 2026-07-03 OWASP review judged this acceptable
/// *because* the SPA is hardened against script injection in the first
/// place: it's a CanvasKit/wasm-rendered app (no DOM text nodes to inject
/// into), ships no inline scripts, and `pb_hooks/web_headers.pb.js` serves a
/// same-origin `script-src 'self'` CSP with no `unsafe-inline`/`unsafe-eval`.
///
/// That makes the CSP header security-critical to this decision, not just
/// defense-in-depth: **do not** run this app behind `FEDERFALL_CSP=off` (or
/// a proxy that strips the header) without also reworking token storage. If
/// that invariant ever needs to be dropped, the two documented alternatives
/// are a short-TTL token with silent refresh, or in-memory storage backed by
/// an httpOnly cookie set by a reverse proxy.
class PrefsAuthTokenStorage implements AuthTokenStorage {
  static const _key = 'federfall.auth';

  @override
  Future<String?> read() async =>
      (await SharedPreferences.getInstance()).getString(_key);

  @override
  Future<void> write(String data) async =>
      (await SharedPreferences.getInstance()).setString(_key, data);

  @override
  Future<void> delete() async =>
      (await SharedPreferences.getInstance()).remove(_key);
}

/// Selects the right [AuthTokenStorage] for the current platform.
@Riverpod(keepAlive: true)
AuthTokenStorage authTokenStorage(Ref ref) =>
    kIsWeb ? PrefsAuthTokenStorage() : SecureAuthTokenStorage();
