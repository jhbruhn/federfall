import 'dart:convert';

import 'package:federfall/core/pocketbase/auth_token_storage.dart';
import 'package:federfall/core/pocketbase/pocketbase_provider.dart';
import 'package:federfall/core/pocketbase/user_agent_client.dart';
import 'package:federfall/core/server/server_config_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Cold start with the server URL already persisted: switching servers via
  // setServerUrl would (deliberately) purge any seeded auth payload.
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'federfall.serverUrl': 'https://pigeons.example',
    }),
  );

  Future<ProviderContainer> configuredContainer(
    FakeAuthTokenStorage storage,
  ) async {
    final container = ProviderContainer(
      overrides: [
        authTokenStorageProvider.overrideWithValue(storage),
        // PackageInfo has no platform channel in unit tests.
        userAgentProvider.overrideWith((ref) => 'federfall/test'),
      ],
    );
    addTearDown(container.dispose);
    await container.read(serverConfigControllerProvider.future);
    return container;
  }

  test('builds a client pointed at the configured base URL', () async {
    final container = await configuredContainer(FakeAuthTokenStorage());

    final pb = await container.read(pocketBaseProvider.future);

    expect(pb.baseURL, 'https://pigeons.example');
  });

  test('persists auth payload through the storage on save', () async {
    final storage = FakeAuthTokenStorage();
    final container = await configuredContainer(storage);

    final pb = await container.read(pocketBaseProvider.future);
    pb.authStore.save('tok-123', null);
    // AsyncAuthStore writes are queued; let the microtasks drain.
    await Future<void>.delayed(Duration.zero);

    expect(storage.value, isNotNull);
    expect(jsonDecode(storage.value!), containsPair('token', 'tok-123'));
  });

  test('restores a persisted session into the auth store', () async {
    final seeded = jsonEncode({'token': 'restored-tok', 'model': null});
    final container = await configuredContainer(FakeAuthTokenStorage(seeded));

    final pb = await container.read(pocketBaseProvider.future);

    expect(pb.authStore.token, 'restored-tok');
  });
}
