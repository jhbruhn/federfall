import 'package:federfall/core/pocketbase/auth_token_storage.dart';
import 'package:federfall/core/server/server_config.dart';
import 'package:federfall/core/server/server_config_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/helpers.dart';

void main() {
  // These tests run on the Dart VM, so `kIsWeb` is false and the native
  // resolution path (persisted URL / unconfigured) is exercised.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  ProviderContainer makeContainer(FakeAuthTokenStorage tokens) {
    final container = ProviderContainer(
      overrides: [authTokenStorageProvider.overrideWithValue(tokens)],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('starts unconfigured on native with no stored URL', () async {
    final container = makeContainer(FakeAuthTokenStorage());

    final config = await container.read(serverConfigControllerProvider.future);

    expect(config, isA<ServerUnconfigured>());
    expect(config.baseUrlOrNull, isNull);
  });

  test('setServerUrl persists and switches to configured', () async {
    final container = makeContainer(FakeAuthTokenStorage());

    await container.read(serverConfigControllerProvider.future);
    await container
        .read(serverConfigControllerProvider.notifier)
        .setServerUrl('https://pigeons.example');

    final config = container.read(serverConfigControllerProvider).requireValue;
    expect(config, const ServerConfig.configured('https://pigeons.example'));

    // Persisted across a fresh container.
    final container2 = makeContainer(FakeAuthTokenStorage());
    final reloaded = await container2.read(
      serverConfigControllerProvider.future,
    );
    expect(reloaded.baseUrlOrNull, 'https://pigeons.example');
  });

  test('clearServerUrl returns to the setup gate', () async {
    final container = makeContainer(FakeAuthTokenStorage());

    final notifier = container.read(serverConfigControllerProvider.notifier);
    await container.read(serverConfigControllerProvider.future);
    await notifier.setServerUrl('https://pigeons.example');
    await notifier.clearServerUrl();

    expect(
      container.read(serverConfigControllerProvider).requireValue,
      isA<ServerUnconfigured>(),
    );
  });

  test(
    'switching to a different server purges the persisted auth payload',
    () async {
      SharedPreferences.setMockInitialValues({
        'federfall.serverUrl': 'https://a.example',
      });
      final tokens = FakeAuthTokenStorage('token-for-a');
      final container = makeContainer(tokens);

      await container.read(serverConfigControllerProvider.future);
      await container
          .read(serverConfigControllerProvider.notifier)
          .setServerUrl('https://b.example');

      // Server A's bearer token must never be sent to server B.
      expect(tokens.value, isNull);
    },
  );

  test('re-setting the same server keeps the session', () async {
    SharedPreferences.setMockInitialValues({
      'federfall.serverUrl': 'https://a.example',
    });
    final tokens = FakeAuthTokenStorage('token-for-a');
    final container = makeContainer(tokens);

    await container.read(serverConfigControllerProvider.future);
    await container
        .read(serverConfigControllerProvider.notifier)
        .setServerUrl('https://a.example');

    expect(tokens.value, 'token-for-a');
  });

  test('clearServerUrl purges the persisted auth payload', () async {
    SharedPreferences.setMockInitialValues({
      'federfall.serverUrl': 'https://a.example',
    });
    final tokens = FakeAuthTokenStorage('token-for-a');
    final container = makeContainer(tokens);

    await container.read(serverConfigControllerProvider.future);
    await container
        .read(serverConfigControllerProvider.notifier)
        .clearServerUrl();

    expect(tokens.value, isNull);
  });
}
