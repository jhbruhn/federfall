import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/animals/merge_animal_screen.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/features/cases/exams/exams_providers.dart';
import 'package:federfall/features/cases/markings/markings_providers.dart';
import 'package:federfall/features/cases/weights/weights_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart' hide Finder;
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class MockAnimalsRepo extends Mock implements PbAnimalsRepository {}

const _current = Animal(id: 'a1', species: 'Stadttaube', name: 'Pip');
const _candidate = Animal(id: 'a2', species: 'Stadttaube', name: 'Kiki');

Future<void> _pump(
  WidgetTester tester, {
  required PbAnimalsRepository animals,
}) async {
  // A tall surface so every section (down to the Merge button) lays out
  // without needing a scroll to become tappable.
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/animals/a1/merge',
        builder: (_, _) => const MergeAnimalScreen(animalId: 'a1'),
      ),
      GoRoute(
        path: '/animals/:id',
        builder: (_, state) =>
            Scaffold(body: Text('ANIMAL ${state.pathParameters['id']}')),
      ),
    ],
    initialLocation: '/animals/a1/merge',
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        animalsRepositoryProvider.overrideWith((ref) async => animals),
        animalByIdProvider('a1').overrideWith((ref) async => _current),
        animalByIdProvider('a2').overrideWith((ref) async => _candidate),
        for (final id in ['a1', 'a2']) ...[
          casesForAnimalProvider(id).overrideWith((ref) async => []),
          markingsForAnimalProvider(id).overrideWith((ref) async => []),
          weightsForAnimalProvider(id).overrideWith((ref) async => []),
          examsForAnimalProvider(id).overrideWith((ref) async => []),
        ],
        reidSearchProvider('kiki').overrideWith(
          (ref) async => [const ReidMatch(animal: _candidate, markings: [])],
        ),
      ],
      child: MaterialApp.router(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Searches for and picks the standing candidate ("Kiki").
Future<void> _pickCandidate(WidgetTester tester) async {
  await tester.enterText(find.byType(TextFormField).first, 'kiki');
  await tester.pump();
  await tester.tap(find.byIcon(Icons.search).last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Kiki · Stadttaube'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    registerFallbackValue('');
    registerFallbackValue(<String, String>{});
  });

  testWidgets('picking a candidate reveals the survivor and field pickers', (
    tester,
  ) async {
    final animals = MockAnimalsRepo();
    await _pump(tester, animals: animals);

    // Only the current animal is shown before a candidate is picked.
    expect(find.text('Pip · Stadttaube'), findsOneWidget);
    expect(find.text('Keep as the primary record'), findsNothing);

    await _pickCandidate(tester);

    // Survivor picker and the differing-name field diff both appear.
    expect(find.text('Keep as the primary record'), findsOneWidget);
    expect(find.text('Name (optional)'), findsOneWidget);
    expect(find.text('Pip'), findsWidgets);
    expect(find.text('Kiki'), findsWidgets);
    // Species agrees on both records, so it gets no picker.
    expect(find.text('Species'), findsNothing);
  });

  testWidgets(
    'submits the merge with the chosen survivor and field picks, '
    'then lands on the surviving record',
    (tester) async {
      final animals = MockAnimalsRepo();
      when(
        () => animals.merge(
          survivor: any(named: 'survivor'),
          duplicate: any(named: 'duplicate'),
          fields: any(named: 'fields'),
        ),
      ).thenAnswer((_) async => 'a1');

      await _pump(tester, animals: animals);
      await _pickCandidate(tester);

      // Keep Kiki's name instead of the default (current animal's) pick. The
      // Name field diff uses the bare name as its segment label ('Kiki'),
      // distinct from the survivor picker's full title ('Kiki · Stadttaube').
      await tester.tap(find.text('Kiki'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Merge'));
      await tester.pumpAndSettle();
      // Confirmation dialog.
      expect(find.text('Merge these animals?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Merge'));
      await tester.pumpAndSettle();

      final captured = verify(
        () => animals.merge(
          survivor: captureAny(named: 'survivor'),
          duplicate: captureAny(named: 'duplicate'),
          fields: captureAny(named: 'fields'),
        ),
      ).captured;
      expect(captured[0], 'a1');
      expect(captured[1], 'a2');
      final fields = captured[2] as Map<String, String>;
      expect(fields['name'], 'duplicate');
      expect(fields['species'], 'survivor');

      // Landed on the surviving record (a1), not left on the merge screen.
      expect(find.text('ANIMAL a1'), findsOneWidget);
    },
  );
}
