import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'last_route_storage.g.dart';

/// Persists the most recently visited in-app location (federfall-7ev8), read
/// back at the next cold start — including one forced by Android reclaiming
/// the process in the background — via `coldStartLocationProvider` in
/// `bootstrap.dart`, so the router can reopen it instead of always landing on
/// the default tab.
class LastRouteStorage {
  static const _key = 'federfall.lastRoute';

  Future<String?> read() async =>
      (await SharedPreferences.getInstance()).getString(_key);

  Future<void> write(String location) async =>
      (await SharedPreferences.getInstance()).setString(_key, location);
}

@Riverpod(keepAlive: true)
LastRouteStorage lastRouteStorage(Ref ref) => LastRouteStorage();
