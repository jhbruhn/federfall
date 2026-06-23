import 'dart:async';

import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/new_case_screen.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class MockAnimalsRepo extends Mock implements PbAnimalsRepository {}

class MockCasesRepo extends Mock implements PbCasesRepository {}

void main() {
  setUpAll(() => registerFallbackValue(<String, dynamic>{}));

  late MockAnimalsRepo animals;
  late MockCasesRepo cases;

  setUp(() {
    animals = MockAnimalsRepo();
    cases = MockCasesRepo();
    when(() => animals.create(any()))
        .thenAnswer((_) async => const Animal(id: 'a1', species: 'Stadttaube'));
    when(() => cases.create(any()))
        .thenAnswer((_) async => const Case(id: 'c1', animal: 'a1'));
  });

  Future<void> pump(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        currentUserProvider.overrideWith(
          (ref) async =>
              const AppUser(id: 'u1', email: 'me@x.org', org: 'org1'),
        ),
        animalsRepositoryProvider.overrideWith((ref) async => animals),
        casesRepositoryProvider.overrideWith((ref) async => cases),
      ],
    );
    addTearDown(container.dispose);

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('HOME')),
        ),
        GoRoute(
          path: '/cases/new',
          builder: (_, _) => const NewCaseScreen(),
        ),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    unawaited(router.push('/cases/new'));
    await tester.pumpAndSettle();
  }

  testWidgets('creates an animal + case and returns to the list',
      (tester) async {
    await pump(tester);

    // Pick a reason (species is pre-filled with the default).
    await tester.tap(find.byType(DropdownButtonFormField<AdmissionReason>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Injury').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Create case'));
    await tester.pumpAndSettle();

    final animalBody =
        verify(() => animals.create(captureAny())).captured.single
            as Map<String, dynamic>;
    expect(animalBody['species'], 'Stadttaube');
    expect(animalBody['org'], 'org1');

    final caseBody = verify(() => cases.create(captureAny())).captured.single
        as Map<String, dynamic>;
    expect(caseBody['animal'], 'a1');
    expect(caseBody['org'], 'org1');
    expect(caseBody['active_carer'], 'u1');
    expect(caseBody['reasons_for_admission'], ['injury']);

    // Popped back to the list.
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('requires a reason before submitting', (tester) async {
    await pump(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Create case'));
    await tester.pumpAndSettle();

    verifyNever(() => animals.create(any()));
    expect(find.text('This field is required'), findsOneWidget);
  });
}
