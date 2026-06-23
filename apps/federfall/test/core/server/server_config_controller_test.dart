import 'package:federfall/core/server/server_config.dart';
import 'package:federfall/core/server/server_config_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // These tests run on the Dart VM, so `kIsWeb` is false and the native
  // resolution path (persisted URL / unconfigured) is exercised.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('starts unconfigured on native with no stored URL', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final config =
        await container.read(serverConfigControllerProvider.future);

    expect(config, isA<ServerUnconfigured>());
    expect(config.baseUrlOrNull, isNull);
  });

  test('setServerUrl persists and switches to configured', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(serverConfigControllerProvider.future);
    await container
        .read(serverConfigControllerProvider.notifier)
        .setServerUrl('https://pigeons.example');

    final config = container.read(serverConfigControllerProvider).requireValue;
    expect(config, const ServerConfig.configured('https://pigeons.example'));

    // Persisted across a fresh container.
    final container2 = ProviderContainer();
    addTearDown(container2.dispose);
    final reloaded =
        await container2.read(serverConfigControllerProvider.future);
    expect(reloaded.baseUrlOrNull, 'https://pigeons.example');
  });

  test('clearServerUrl returns to the setup gate', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier =
        container.read(serverConfigControllerProvider.notifier);
    await container.read(serverConfigControllerProvider.future);
    await notifier.setServerUrl('https://pigeons.example');
    await notifier.clearServerUrl();

    expect(
      container.read(serverConfigControllerProvider).requireValue,
      isA<ServerUnconfigured>(),
    );
  });
}
