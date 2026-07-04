import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/statistics/intake_map_screen.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart' hide Finder;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockCasesRepo extends Mock implements PbCasesRepository {}

class MockAnimalsRepo extends Mock implements PbAnimalsRepository {}

void main() {
  late MockCasesRepo cases;
  late MockAnimalsRepo animals;

  setUp(() {
    cases = MockCasesRepo();
    animals = MockAnimalsRepo();
    when(() => animals.list()).thenAnswer(
      (_) async => const [Animal(id: 'a1', species: 'Columba livia')],
    );
  });

  Future<void> pump(
    WidgetTester tester, {
    UserRole role = UserRole.coordinator,
  }) async {
    final container = ProviderContainer(
      overrides: [
        currentUserProvider.overrideWith(
          (ref) async =>
              AppUser(id: 'u1', email: 'me@x.org', role: role, org: 'org1'),
        ),
        casesRepositoryProvider.overrideWith((ref) async => cases),
        animalsRepositoryProvider.overrideWith((ref) async => animals),
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
          home: IntakeMapScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('plots a pin for each case with a find-location', (
    tester,
  ) async {
    final now = DateTime.now();
    when(() => cases.list()).thenAnswer(
      (_) async => [
        Case(
          id: 'c1',
          animal: 'a1',
          caseNumber: 'F-1',
          admittedAt: now,
          findGeo: const GeoPoint(lat: 52.5, lon: 13.4),
        ),
        // No find-location: excluded regardless of the period filter.
        Case(id: 'c2', animal: 'a1', admittedAt: now),
      ],
    );

    await pump(tester);

    expect(find.byIcon(Icons.location_on), findsOneWidget);
  });

  testWidgets('shows an empty state when nothing has a find-location', (
    tester,
  ) async {
    when(() => cases.list()).thenAnswer(
      (_) async => const [Case(id: 'c1', animal: 'a1')],
    );

    await pump(tester);

    expect(
      find.text('No intakes with a location in this period'),
      findsOneWidget,
    );
  });

  testWidgets('a carer gets the unauthorized view, not the map', (
    tester,
  ) async {
    when(() => cases.list()).thenAnswer((_) async => const []);

    await pump(tester, role: UserRole.carer);

    expect(find.text('You are not authorized to do that'), findsOneWidget);
    expect(find.byIcon(Icons.location_on), findsNothing);
  });
}
