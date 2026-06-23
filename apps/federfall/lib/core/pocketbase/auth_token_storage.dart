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
