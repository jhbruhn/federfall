import 'package:federfall/core/auth/auth_status.dart';
import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/server/server_config.dart';
import 'package:federfall/core/server/server_config_controller.dart';
import 'package:federfall/core/server/server_info_provider.dart';
import 'package:federfall/features/animals/animal_detail_screen.dart';
import 'package:federfall/features/animals/animals_providers.dart';
import 'package:federfall/features/animals/animals_screen.dart';
import 'package:federfall/features/cases/case_detail_screen.dart';
import 'package:federfall/features/cases/cases_browser.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/features/cases/cases_screen.dart';
import 'package:federfall/features/cases/exams/exams_providers.dart';
import 'package:federfall/features/cases/markings/marking_types_providers.dart';
import 'package:federfall/features/cases/weights/weights_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/routing/app_routes.dart';
import 'package:federfall/routing/router.dart';
import 'package:federfall_models/federfall_models.dart' hide Finder;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeServerConfig extends ServerConfigController {
  @override
  Future<ServerConfig> build() async =>
      const ServerConfig.configured('https://x.example');
}

class _FakeAuthStatus extends AuthStatus {
  @override
  Future<bool> build() async => true;
}

Future<ProviderContainer> _pumpPhone(WidgetTester tester) async {
  tester.view
    ..physicalSize = const Size(400, 800)
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer(
    overrides: [
      serverConfigControllerProvider.overrideWith(_FakeServerConfig.new),
      authStatusProvider.overrideWith(_FakeAuthStatus.new),
      serverInfoProvider.overrideWith((ref) async => null),
      currentUserProvider.overrideWith((ref) async => null),
      casesBrowserDataProvider.overrideWith(
        (ref) async => const CasesBrowserData(
          cases: [],
          animalsById: {},
          myUserId: 'u1',
        ),
      ),
      animalsRegistryProvider.overrideWith(
        (ref) async => const [
          AnimalListItem(
            animal: Animal(id: 'a1', species: 'Columba livia', name: 'Pip'),
            codes: [],
          ),
        ],
      ),
      animalLifetimeProvider('a1').overrideWith(
        (ref) async => const AnimalLifetime(
          animal: Animal(id: 'a1', species: 'Columba livia', name: 'Pip'),
          markings: [],
          cases: [],
          accessibleCaseIds: {},
        ),
      ),
      weightsForAnimalProvider('a1').overrideWith((ref) async => const []),
      examsForAnimalProvider('a1').overrideWith((ref) async => const []),
      markingTypesProvider.overrideWith((ref) async => const []),
      caseByIdProvider(
        'c1',
      ).overrideWith((ref) async => const Case(id: 'c1', animal: 'a1')),
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
  return container;
}

void main() {
  // Regression: a cross-branch go() (animal detail → its case) parks the
  // animals branch on /animals/:id. On a phone the bottom bar is hidden on a
  // detail, so re-tapping the Animals tab used to restore that stale detail
  // full-screen with no bottom bar — the user could only escape via the app-bar
  // back and tapping the "list" did nothing. A compact tab tap must always land
  // on the section's list.
  testWidgets(
    'tapping a tab after a cross-branch go() returns to the list, not a '
    'stranded detail (federfall-7ev8)',
    (tester) async {
      final container = await _pumpPhone(tester);
      final router = container.read(routerProvider);

      // Animals tab → animal detail (mirrors the list tile's go()).
      await tester.tap(find.text('Tiere').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pip'));
      await tester.pumpAndSettle();
      expect(find.byType(AnimalDetailScreen), findsOneWidget);

      // Tap "the case" from the animal detail: a cross-branch go() that leaves
      // the animals branch parked on /animals/a1 and switches to cases.
      router.go(AppRoutes.caseDetail('c1'));
      await tester.pumpAndSettle();
      expect(find.byType(CaseDetailScreen), findsOneWidget);

      // Back → the cases list (bottom bar returns).
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(CasesScreen), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);

      // Tap the Animals tab again: must show the LIST with the bottom bar, not
      // the stranded /animals/a1 detail.
      await tester.tap(find.text('Tiere').last);
      await tester.pumpAndSettle();
      expect(find.byType(AnimalsScreen), findsOneWidget);
      expect(find.byType(AnimalDetailScreen), findsNothing);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        AppRoutes.animals,
      );
    },
  );
}
