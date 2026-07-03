import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/animals/animal_detail_screen.dart';
import 'package:federfall/features/animals/animals_providers.dart';
import 'package:federfall/features/cases/exams/exams_providers.dart';
import 'package:federfall/features/cases/markings/marking_types_providers.dart';
import 'package:federfall/features/cases/weights/weights_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAnimalsRepo extends Mock implements PbAnimalsRepository {}

Future<void> _pump(
  WidgetTester tester,
  AnimalLifetime lifetime, {
  List<Weight> weights = const [],
  List<Exam> exams = const [],
  PbAnimalsRepository? animals,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        animalLifetimeProvider(
          'a1',
        ).overrideWith((ref) async => lifetime),
        weightsForAnimalProvider('a1').overrideWith((ref) async => weights),
        examsForAnimalProvider('a1').overrideWith((ref) async => exams),
        markingTypesProvider.overrideWith(
          (ref) async => const [
            MarkingType(id: 'mktp_assoc', label: 'Association ring'),
          ],
        ),
        if (animals != null)
          animalsRepositoryProvider.overrideWith((ref) async => animals),
      ],
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AnimalDetailScreen(animalId: 'a1'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => registerFallbackValue(<String, dynamic>{}));

  testWidgets('editing identity saves species/name/sex via the repo', (
    tester,
  ) async {
    final animals = MockAnimalsRepo();
    when(() => animals.update(any(), any())).thenAnswer(
      (_) async => const Animal(id: 'a1', species: 'Columba livia'),
    );

    await _pump(
      tester,
      const AnimalLifetime(
        animal: Animal(id: 'a1', species: 'Colmba livia', name: 'Pip'),
        markings: [],
        cases: [],
        accessibleCaseIds: {},
      ),
      animals: animals,
    );

    await tester.tap(find.byTooltip('Edit animal'));
    await tester.pumpAndSettle();

    // Fix the species typo and save.
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Species'),
      'Columba livia',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final data =
        verify(() => animals.update('a1', captureAny())).captured.single
            as Map<String, dynamic>;
    expect(data['species'], 'Columba livia');
    expect(data['name'], 'Pip');
  });

  testWidgets('shows identity, markings and all cases', (tester) async {
    await _pump(
      tester,
      const AnimalLifetime(
        animal: Animal(
          id: 'a1',
          species: 'Columba livia',
          name: 'Pip',
          lifetimeStatus: LifetimeStatus.atLargeReleased,
        ),
        markings: [
          Marking(
            id: 'm1',
            animal: 'a1',
            type: 'mktp_assoc',
            code: 'DE-1234',
            isActive: true,
          ),
        ],
        cases: [
          CaseSummary(
            id: 'c1',
            animal: 'a1',
            caseNumber: '2026-001',
            status: CaseStatus.disposed,
          ),
          CaseSummary(
            id: 'c2',
            animal: 'a1',
            caseNumber: '2026-009',
            status: CaseStatus.inCare,
          ),
        ],
        accessibleCaseIds: {'c1'},
      ),
    );

    // Name shows in the app bar and the identity card.
    expect(find.text('Pip'), findsWidgets);
    expect(find.text('Released'), findsOneWidget);
    expect(find.textContaining('DE-1234'), findsOneWidget);
    expect(find.text('2026-001'), findsOneWidget);
    expect(find.text('2026-009'), findsOneWidget);
  });

  testWidgets('shows the latest weight and a record action', (tester) async {
    await _pump(
      tester,
      const AnimalLifetime(
        animal: Animal(id: 'a1', species: 'Columba livia', name: 'Pip'),
        markings: [],
        cases: [],
        accessibleCaseIds: {},
      ),
      weights: const [
        Weight(id: 'w1', animal: 'a1', weightG: 240),
        Weight(id: 'w2', animal: 'a1', weightG: 255),
      ],
    );

    // Latest reading (last in the oldest-first list) shown; record action.
    expect(find.text('255 g'), findsOneWidget);
    expect(find.byTooltip('Add weight'), findsOneWidget);
  });

  testWidgets('can apply a marking from the animal detail (no case)', (
    tester,
  ) async {
    await _pump(
      tester,
      const AnimalLifetime(
        animal: Animal(id: 'a1', species: 'Columba livia', name: 'Pip'),
        markings: [],
        cases: [],
        accessibleCaseIds: {},
      ),
    );

    // The markings section offers an "apply marking" action.
    await tester.tap(find.byTooltip('Apply marking'));
    await tester.pumpAndSettle();

    // The marking form opens (no case required).
    expect(find.text('Apply marking'), findsWidgets);
  });

  testWidgets('marks inaccessible cases as non-tappable stubs', (tester) async {
    await _pump(
      tester,
      const AnimalLifetime(
        animal: Animal(id: 'a1', species: 'Columba livia', name: 'Pip'),
        markings: [],
        cases: [
          CaseSummary(
            id: 'c1',
            animal: 'a1',
            caseNumber: '2026-001',
            status: CaseStatus.inCare,
          ),
          CaseSummary(
            id: 'c2',
            animal: 'a1',
            caseNumber: '2026-002',
            status: CaseStatus.inCare,
          ),
        ],
        accessibleCaseIds: {'c1'},
      ),
    );

    // The inaccessible case (c2) carries the no-access badge; the accessible
    // one (c1) does not.
    expect(find.textContaining('No access'), findsOneWidget);

    // Accessible case is tappable (chevron); inaccessible is disabled.
    final accessibleTile = tester.widget<ListTile>(
      find.ancestor(
        of: find.text('2026-001'),
        matching: find.byType(ListTile),
      ),
    );
    final stubTile = tester.widget<ListTile>(
      find.ancestor(
        of: find.text('2026-002'),
        matching: find.byType(ListTile),
      ),
    );
    expect(accessibleTile.enabled, isTrue);
    expect(accessibleTile.onTap, isNotNull);
    expect(stubTile.enabled, isFalse);
    expect(stubTile.onTap, isNull);
  });

  testWidgets('lists the animal lifetime exams with a vitals summary', (
    tester,
  ) async {
    await _pump(
      tester,
      const AnimalLifetime(
        animal: Animal(id: 'a1', species: 'Columba livia', name: 'Pip'),
        markings: [],
        cases: [],
        accessibleCaseIds: {},
      ),
      exams: const [
        Exam(
          id: 'e1',
          caseId: 'c1',
          animal: 'a1',
          bodyCondition: 3,
          hydration: Hydration.moderate,
        ),
      ],
    );

    expect(find.text('Exams'), findsOneWidget);
    expect(find.textContaining('BC 3/5'), findsOneWidget);
  });

  testWidgets('shows empty states with no markings or cases', (tester) async {
    await _pump(
      tester,
      const AnimalLifetime(
        animal: Animal(id: 'a1', species: 'Columba livia', name: 'Pip'),
        markings: [],
        cases: [],
        accessibleCaseIds: {},
      ),
    );

    expect(find.text('No markings recorded'), findsOneWidget);
    expect(find.text('No cases recorded'), findsOneWidget);
    expect(find.text('No exams recorded'), findsOneWidget);
  });
}
