import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/placements/placement_sheet.dart';
import 'package:federfall/features/cases/placements/placement_tile.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockPlacementsRepo extends Mock implements PbPlacementsRepository {}

class MockUsersRepo extends Mock implements PbUsersRepository {}

class MockCasesRepo extends Mock implements PbCasesRepository {}

void main() {
  setUpAll(() => registerFallbackValue(<String, dynamic>{}));

  late MockPlacementsRepo placements;
  late MockUsersRepo users;
  late MockCasesRepo cases;

  const members = [
    AppUser(id: 'u1', email: 'a@x.org', name: 'Alice'),
    AppUser(id: 'u2', email: 'b@x.org', name: 'Bob'),
  ];
  const medicalCase = Case(id: 'c1', animal: 'an1', activeCarer: 'u1');

  setUp(() {
    placements = MockPlacementsRepo();
    users = MockUsersRepo();
    cases = MockCasesRepo();
    when(() => users.activeMembers()).thenAnswer((_) async => members);
    when(() => placements.create(any())).thenAnswer(
      (_) async => const Placement(id: 'p1', caseId: 'c1'),
    );
    when(() => cases.update(any(), any())).thenAnswer(
      (_) async => medicalCase,
    );
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
    final container = ProviderContainer(
      overrides: [
        currentUserProvider.overrideWith(
          (ref) async =>
              const AppUser(id: 'u1', email: 'a@x.org', org: 'org1'),
        ),
        placementsRepositoryProvider.overrideWith((ref) async => placements),
        usersRepositoryProvider.overrideWith((ref) async => users),
        casesRepositoryProvider.overrideWith((ref) async => cases),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: child),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    final submit = find.widgetWithText(FilledButton, 'Save');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
  }

  testWidgets('choosing a different carer hands the case off', (tester) async {
    await pump(tester, const PlacementSheet(medicalCase: medicalCase));

    // Switch carer from Alice (current) to Bob.
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bob').last);
    await tester.pumpAndSettle();
    await save(tester);

    // The case's active carer is updated (hook then auto-shares Alice).
    final caseBody = verify(() => cases.update('c1', captureAny()))
        .captured
        .single as Map<String, dynamic>;
    expect(caseBody['active_carer'], 'u2');

    final body = verify(() => placements.create(captureAny())).captured.single
        as Map<String, dynamic>;
    expect(body['from_user'], 'u1');
    expect(body['to_user'], 'u2');
  });

  testWidgets('keeping the same carer records a move, no handoff',
      (tester) async {
    await pump(tester, const PlacementSheet(medicalCase: medicalCase));

    await tester.enterText(
      find.ancestor(
        of: find.text('Enclosure'),
        matching: find.byType(TextField),
      ),
      'Aviary 2',
    );
    await save(tester);

    verifyNever(() => cases.update(any(), any()));
    final body = verify(() => placements.create(captureAny())).captured.single
        as Map<String, dynamic>;
    expect(body['enclosure'], 'Aviary 2');
    expect(body['to_user'], isNull);
  });

  testWidgets('placement tile shows a handoff and its target', (tester) async {
    when(() => placements.forCase(any())).thenAnswer((_) async => []);

    await pump(
      tester,
      const PlacementTile(
        placement: Placement(
          id: 'p1',
          caseId: 'c1',
          toUser: 'u2',
          enclosure: 'Aviary 2',
        ),
        medicalCase: medicalCase,
      ),
    );

    expect(find.text('Handed off to Bob'), findsOneWidget);
    expect(find.text('Aviary 2'), findsOneWidget);
  });
}
