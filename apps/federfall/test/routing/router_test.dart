import 'dart:async';
import 'package:federfall/core/auth/auth_status.dart';
import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/server/server_config.dart';
import 'package:federfall/core/server/server_config_controller.dart';
import 'package:federfall/features/auth/confirm_reset_screen.dart';
import 'package:federfall/features/auth/login_screen.dart';
import 'package:federfall/features/cases/case_detail_screen.dart';
import 'package:federfall/features/cases/cases_browser.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/features/cases/cases_screen.dart';
import 'package:federfall/features/server_setup/setup_screen.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/routing/app_routes.dart';
import 'package:federfall/routing/router.dart';
import 'package:federfall_models/federfall_models.dart';
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

Future<ProviderContainer> _pumpAt(
  WidgetTester tester, {
  required ServerConfig config,
  required bool authed,
}) {
  final container = ProviderContainer(
    overrides: [
      serverConfigControllerProvider.overrideWith(
        () => _FakeServerConfig(config),
      ),
      authStatusProvider.overrideWith(() => _FakeAuthStatus(authed: authed)),
      casesBrowserDataProvider.overrideWith(
        (ref) async => const CasesBrowserData(
          cases: [],
          animalsById: {},
          myUserId: 'u1',
        ),
      ),
      currentUserProvider.overrideWith((ref) async => null),
    ],
  );
  return _pumpContainer(tester, container);
}

Future<ProviderContainer> _pumpContainer(
  WidgetTester tester,
  ProviderContainer container,
) async {
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
  return container;
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

  testWidgets('configured + authenticated → cases tab', (tester) async {
    await _pumpAt(
      tester,
      config: const ServerConfig.configured('https://x.example'),
      authed: true,
    );
    expect(find.byType(CasesScreen), findsOneWidget);
  });

  testWidgets('case detail is reachable at /cases/:id', (tester) async {
    final container = ProviderContainer(
      overrides: [
        serverConfigControllerProvider.overrideWith(
          () => _FakeServerConfig(
            const ServerConfig.configured('https://x.example'),
          ),
        ),
        authStatusProvider.overrideWith(() => _FakeAuthStatus(authed: true)),
        casesBrowserDataProvider.overrideWith(
          (ref) async => const CasesBrowserData(
            cases: [],
            animalsById: {},
            myUserId: 'u1',
          ),
        ),
        currentUserProvider.overrideWith((ref) async => null),
        caseByIdProvider(
          'c1',
        ).overrideWith((ref) async => const Case(id: 'c1', animal: 'a1')),
      ],
    );
    await _pumpContainer(tester, container);

    final router = container.read(routerProvider)
      ..go(AppRoutes.caseDetail('c1'));
    await tester.pumpAndSettle();

    expect(find.byType(CaseDetailScreen), findsOneWidget);
    // The address bar must track the detail page (nested under the cases
    // branch + go, so the shell no longer owns the URL).
    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      '/cases/c1',
    );
  });

  testWidgets('a pushed /cases/browse applies the deep-linked filter', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        serverConfigControllerProvider.overrideWith(
          () => _FakeServerConfig(
            const ServerConfig.configured('https://x.example'),
          ),
        ),
        authStatusProvider.overrideWith(() => _FakeAuthStatus(authed: true)),
        casesBrowserDataProvider.overrideWith(
          (ref) async => const CasesBrowserData(
            // Owned by someone else: only visible under scope=all.
            cases: [
              Case(
                id: 'c1',
                animal: 'a1',
                caseNumber: '2026-099',
                activeCarer: 'other',
                status: CaseStatus.inCare,
              ),
            ],
            animalsById: {},
            myUserId: 'u1',
          ),
        ),
        currentUserProvider.overrideWith((ref) async => null),
      ],
    );
    await _pumpContainer(tester, container);

    unawaited(
      container
          .read(routerProvider)
          .push(AppRoutes.casesBrowse('scope=all&activity=active')),
    );
    await tester.pumpAndSettle();

    // The transient browser renders and the scope=all filter reveals the
    // other carer's case (hidden under the default "mine" scope).
    expect(find.byType(CasesScreen), findsOneWidget);
    expect(find.text('2026-099'), findsOneWidget);
  });

  testWidgets('confirm-reset is reachable without a session', (tester) async {
    final container = await _pumpAt(
      tester,
      config: const ServerConfig.configured('https://x.example'),
      authed: false,
    );

    container.read(routerProvider).go('${AppRoutes.confirmReset}?token=abc');
    await tester.pumpAndSettle();

    expect(find.byType(ConfirmResetScreen), findsOneWidget);
  });
}
