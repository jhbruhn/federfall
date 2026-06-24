import 'package:federfall/features/animals/animal_detail_screen.dart';
import 'package:federfall/features/animals/animals_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, AnimalLifetime lifetime) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        animalLifetimeProvider(
          'a1',
        ).overrideWith((ref) async => lifetime),
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
            type: MarkingType.associationRing,
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

  testWidgets('can apply a marking from the animal detail (no case)',
      (tester) async {
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

  testWidgets('marks inaccessible cases as non-tappable stubs',
      (tester) async {
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
  });
}
