import 'package:federfall/core/auth/auth_status.dart';
import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/server/server_config.dart';
import 'package:federfall/core/server/server_config_controller.dart';
import 'package:federfall/features/animals/animals_providers.dart';
import 'package:federfall/features/animals/animals_screen.dart';
import 'package:federfall/features/cases/cases_browser.dart';
import 'package:federfall/features/cases/cases_screen.dart';
import 'package:federfall/features/dashboard/dashboard_providers.dart';
import 'package:federfall/features/dashboard/dashboard_screen.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/routing/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Authenticated, configured-server fakes so the router lands in the shell.
class _FakeServerConfig extends ServerConfigController {
  @override
  Future<ServerConfig> build() async =>
      const ServerConfig.configured('https://x.example');
}

class _FakeAuthStatus extends AuthStatus {
  @override
  Future<bool> build() async => true;
}

Future<void> _pump(WidgetTester tester, {required Size size}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer(
    overrides: [
      serverConfigControllerProvider.overrideWith(_FakeServerConfig.new),
      authStatusProvider.overrideWith(_FakeAuthStatus.new),
      casesBrowserDataProvider.overrideWith(
        (ref) async => const CasesBrowserData(
          cases: [],
          animalsById: {},
          myUserId: 'u1',
        ),
      ),
      animalsRegistryProvider.overrideWith(
        (ref) async => const <AnimalListItem>[],
      ),
      currentUserProvider.overrideWith((ref) async => null),
      dashboardSummaryProvider.overrideWith(
        (ref) async => const DashboardSummary(
          activeCount: 0,
          intakesThisYear: 0,
          byStatus: {},
          quarantineEndingSoon: [],
        ),
      ),
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
  testWidgets('narrow screens use a bottom NavigationBar', (tester) async {
    await _pump(tester, size: const Size(400, 800));

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(CasesScreen), findsOneWidget);
  });

  testWidgets('wide screens use a NavigationRail', (tester) async {
    await _pump(tester, size: const Size(1200, 800));

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('switching destinations swaps the active tab', (tester) async {
    await _pump(tester, size: const Size(400, 800));
    expect(find.byType(CasesScreen), findsOneWidget);

    await tester.tap(find.text('Tiere').last);
    await tester.pumpAndSettle();
    expect(find.byType(AnimalsScreen), findsOneWidget);

    await tester.tap(find.text('Übersicht').last);
    await tester.pumpAndSettle();
    expect(find.byType(DashboardScreen), findsOneWidget);
  });
}
