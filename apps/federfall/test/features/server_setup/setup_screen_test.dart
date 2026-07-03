import 'package:federfall/core/pocketbase/auth_token_storage.dart';
import 'package:federfall/core/server/server_config.dart';
import 'package:federfall/core/server/server_config_controller.dart';
import 'package:federfall/core/server/server_probe.dart';
import 'package:federfall/features/server_setup/setup_screen.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/helpers.dart';

/// A minimal valid `/api/federfall/info` body for a probed server.
Map<String, Object?> _infoBody() => {
  'service': 'federfall',
  'federfall': true,
  'version': '1.0.0',
  'name': 'Federfall',
  'auth': {'password': true},
};

Future<ProviderContainer> _pump(WidgetTester tester, ServerProbe probe) async {
  final container = ProviderContainer(
    overrides: [
      serverProbeProvider.overrideWithValue(probe),
      authTokenStorageProvider.overrideWithValue(FakeAuthTokenStorage()),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SetupScreen(),
      ),
    ),
  );
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows an inline error when the server is unreachable', (
    tester,
  ) async {
    await _pump(tester, ServerProbe((_) async => throw ClientException()));

    await tester.enterText(find.byType(TextFormField), 'pigeons.example');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not reach the server'), findsOneWidget);
  });

  testWidgets('persists the normalised URL on a successful probe', (
    tester,
  ) async {
    final container = await _pump(
      tester,
      ServerProbe((_) async => _infoBody()),
    );

    await tester.enterText(find.byType(TextFormField), 'pigeons.example');
    await tester.tap(find.text('Connect'));
    // Can't pumpAndSettle: the success path leaves the button spinner running
    // (the router would redirect away), so pump fixed frames to let the async
    // probe + persist resolve.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final config = container.read(serverConfigControllerProvider).requireValue;
    expect(config, const ServerConfig.configured('https://pigeons.example'));
  });

  testWidgets('shows an inline error for an explicit http:// address', (
    tester,
  ) async {
    var probed = false;
    await _pump(
      tester,
      ServerProbe((_) async {
        probed = true;
        return _infoBody();
      }),
    );

    await tester.enterText(
      find.byType(TextFormField),
      'http://pigeons.example',
    );
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();

    expect(probed, isFalse);
    expect(find.textContaining('unencrypted'), findsOneWidget);
  });

  testWidgets('blocks submission when the field is empty', (tester) async {
    var probed = false;
    await _pump(
      tester,
      ServerProbe((_) async {
        probed = true;
        return _infoBody();
      }),
    );

    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();

    expect(probed, isFalse);
    expect(find.text('This field is required'), findsOneWidget);
  });
}
