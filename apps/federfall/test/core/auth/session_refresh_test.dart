import 'package:federfall/core/auth/session_refresh.dart';
import 'package:federfall/core/server/server_config.dart';
import 'package:federfall/core/server/server_config_controller.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class _FakeServerConfig extends ServerConfigController {
  _FakeServerConfig(this._config);
  final ServerConfig _config;
  @override
  Future<ServerConfig> build() async => _config;
}

/// Server config that never resolves to `ServerConfigured` (setup incomplete).
class _UnconfiguredServer extends ServerConfigController {
  @override
  Future<ServerConfig> build() async => const ServerUnconfigured();
}

void main() {
  // AppLifecycleListener (created inside the provider) needs a live binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockAuthRepository auth;

  setUp(() {
    auth = MockAuthRepository();
    when(() => auth.refresh()).thenAnswer((_) async => null);
  });

  test(
    'rolls the session once at startup when a server is configured',
    () async {
      final container = ProviderContainer(
        overrides: [
          serverConfigControllerProvider.overrideWith(
            () =>
                _FakeServerConfig(const ServerConfigured('https://pb.example')),
          ),
          authRepositoryProvider.overrideWith((ref) async => auth),
        ],
      );
      addTearDown(container.dispose);

      await container.read(sessionRefreshProvider.future);
      // The startup refresh is fired unawaited inside the provider; let it run.
      await Future<void>.delayed(Duration.zero);

      verify(() => auth.refresh()).called(1);
    },
  );

  test('does not touch the repo until a server is configured', () async {
    var repoResolved = false;
    final container = ProviderContainer(
      overrides: [
        serverConfigControllerProvider.overrideWith(_UnconfiguredServer.new),
        authRepositoryProvider.overrideWith((ref) async {
          repoResolved = true;
          return auth;
        }),
      ],
    );
    addTearDown(container.dispose);

    await container.read(sessionRefreshProvider.future);
    await Future<void>.delayed(Duration.zero);

    expect(repoResolved, isFalse);
    verifyNever(() => auth.refresh());
  });

  test(
    'swallows a refresh failure so a network blip cannot log the user out',
    () async {
      when(() => auth.refresh()).thenThrow(
        const RepositoryException(
          'offline',
          kind: RepositoryErrorKind.network,
        ),
      );
      final container = ProviderContainer(
        overrides: [
          serverConfigControllerProvider.overrideWith(
            () =>
                _FakeServerConfig(const ServerConfigured('https://pb.example')),
          ),
          authRepositoryProvider.overrideWith((ref) async => auth),
        ],
      );
      addTearDown(container.dispose);

      // The provider must still complete normally despite refresh throwing.
      await expectLater(
        container.read(sessionRefreshProvider.future),
        completes,
      );
      await Future<void>.delayed(Duration.zero);
      verify(() => auth.refresh()).called(1);
    },
  );
}
