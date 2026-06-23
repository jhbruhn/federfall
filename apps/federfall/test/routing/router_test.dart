import 'package:federfall/core/auth/auth_status.dart';
import 'package:federfall/core/server/server_config.dart';
import 'package:federfall/core/server/server_config_controller.dart';
import 'package:federfall/features/auth/login_screen.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/features/home/home_screen.dart';
import 'package:federfall/features/server_setup/setup_screen.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/routing/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake that resolves to a fixed server config.
class _FakeServerConfig extends ServerConfigController {
  _FakeServerConfig(this._config);
  final ServerConfig _config;
  @override
  Future<ServerConfig> build() async => _config;
}

/// Fake that resolves to a fixed auth status.
class _FakeAuthStatus extends AuthStatus {
  _FakeAuthStatus({required this.authed});
  final bool authed;
  @override
  Future<bool> build() async => authed;
}

Future<void> _pumpAt(
  WidgetTester tester, {
  required ServerConfig config,
  required bool authed,
}) async {
  final container = ProviderContainer(
    overrides: [
      serverConfigControllerProvider.overrideWith(
        () => _FakeServerConfig(config),
      ),
      authStatusProvider.overrideWith(() => _FakeAuthStatus(authed: authed)),
      // HomeScreen reads this; stub it so the routing test never touches the
      // real PocketBase client.
      myCasesProvider.overrideWith((ref) async => const <Case>[]),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: Consumer(
        builder: (context, ref, _) => MaterialApp.router(
          locale: const Locale('de'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: ref.watch(routerProvider),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('unconfigured server → setup', (tester) async {
    await _pumpAt(
      tester,
      config: const ServerConfig.unconfigured(),
      authed: false,
    );
    expect(find.byType(SetupScreen), findsOneWidget);
  });

  testWidgets('configured + unauthenticated → login', (tester) async {
    await _pumpAt(
      tester,
      config: const ServerConfig.configured('https://x.example'),
      authed: false,
    );
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('configured + authenticated → home', (tester) async {
    await _pumpAt(
      tester,
      config: const ServerConfig.configured('https://x.example'),
      authed: true,
    );
    expect(find.byType(HomeScreen), findsOneWidget);
  });
}
