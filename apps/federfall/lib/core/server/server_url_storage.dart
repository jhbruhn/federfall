import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'server_url_storage.g.dart';

/// Persists the native-only, user-entered server URL (FED-3.0). Not secret, so
/// plain `shared_preferences` rather than the keychain. Web never reads this —
/// its base URL is the serving origin.
class ServerUrlStorage {
  static const _key = 'federfall.serverUrl';

  Future<String?> read() async =>
      (await SharedPreferences.getInstance()).getString(_key);

  Future<void> write(String url) async =>
      (await SharedPreferences.getInstance()).setString(_key, url);

  Future<void> delete() async =>
      (await SharedPreferences.getInstance()).remove(_key);
}

@Riverpod(keepAlive: true)
ServerUrlStorage serverUrlStorage(Ref ref) => ServerUrlStorage();
