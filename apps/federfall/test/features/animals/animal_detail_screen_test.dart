import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/animals/animal_detail_screen.dart';
import 'package:federfall/features/animals/animals_providers.dart';
import 'package:federfall/features/animals/custody_providers.dart';
import 'package:federfall/features/cases/eggs/eggs_providers.dart';
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
  List<EggRecord> eggs = const [],
  bool eggsError = false,
  List<Exam> exams = const [],
  UserRole? role,
  PbAnimalsRepository? animals,
  bool canWrite = true,
  bool canOpenCase = true,
}) async {
  // The detail is a lazy ListView of cards; the default 600x800 test viewport
  // stops building at the weight card, so later sections would never mount.
  tester.view.physicalSize = const Size(1000, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        animalLifetimeProvider(
          'a1',
        ).overrideWith((ref) async => lifetime),
        weightsForAnimalProvider('a1').overrideWith((ref) async => weights),
        eggsForAnimalProvider('a1').overrideWith(
          (ref) async => eggsError ? throw Exception('boom') : eggs,
        ),
        examsForAnimalProvider('a1').overrideWith((ref) async => exams),
        currentUserProvider.overrideWith(
          (ref) async => role == null
              ? null
              : AppUser(id: 'me', email: 'me@x.org', org: 'org1', role: role),
        ),
        markingTypesProvider.overrideWith(
          (ref) async => const [
            MarkingType(id: 'mktp_assoc', label: 'Association ring'),
          ],
        ),
        // Custody, stated explicitly. Every write control on this screen is
        // gated on it (1700000077/79), so a fixture that left it unresolved
        // would render no controls and each assertion below would pass for the
        // wrong reason. The predicate itself is covered in roles_test.dart.
        canWriteAnimalProvider('a1').overrideWith((ref) async => canWrite),
        canOpenCaseOnAnimalProvider(
          'a1',
        ).overrideWith((ref) async => canOpenCase),
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
    expect(find.text('No egg records'), findsOneWidget);
  });

  testWidgets('summarises the laying history with the unconfirmed count', (
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
      eggs: [
        EggRecord(
          id: 'e1',
          animal: 'a1',
          count: 2,
          laidAt: DateTime(2026, 6, 2),
        ),
        EggRecord(
          id: 'e2',
          animal: 'a1',
          laidAt: DateTime(2026, 6, 24),
          attribution: EggAttribution.presumed,
        ),
      ],
    );

    // Counts sum `count`, so two rows are three eggs.
    expect(find.text('3 eggs in 12 months · 3 in total'), findsOneWidget);
    // The two records are 22 days apart, so they read as two clutches — but
    // only a clutch holding more than one record earns a subheading; a
    // one-record header would just repeat its row.
    expect(find.text('CLUTCH · JUN 2, 2026 · 2 EGGS'), findsNothing);
    expect(find.text('CLUTCH · JUN 24, 2026 · 1 EGG'), findsNothing);
    // A guess stays flagged instead of hardening into the totals above it.
    expect(find.text('1 unconfirmed'), findsOneWidget);
    expect(find.text('presumed'), findsOneWidget);
    expect(find.text('No egg records'), findsNothing);
  });

  testWidgets('an egg load failure is an error with a retry, not "no eggs"', (
    tester,
  ) async {
    await _pump(
      tester,
      const AnimalLifetime(
        animal: Animal(id: 'a1', species: 'Columba livia'),
        markings: [],
        cases: [],
        accessibleCaseIds: {},
      ),
      eggsError: true,
    );

    expect(find.text('No egg records'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Retry'), findsWidgets);
  });

  testWidgets('the egg card caps its rows however long a clutch runs', (
    tester,
  ) async {
    // Ten records two days apart derive as ONE clutch (the gap is five days),
    // so without a row cap the card would render all ten.
    await _pump(
      tester,
      const AnimalLifetime(
        animal: Animal(id: 'a1', species: 'Columba livia'),
        markings: [],
        cases: [],
        accessibleCaseIds: {},
      ),
      eggs: [
        for (var i = 0; i < 10; i++)
          EggRecord(
            id: 'e$i',
            animal: 'a1',
            laidAt: DateTime(2026, 6, 1 + i * 2),
          ),
      ],
    );

    // Every egg still counts toward the totals...
    expect(find.text('10 eggs in 12 months · 10 in total'), findsOneWidget);
    // ...but only the capped number of rows is listed, under the one
    // subheading that names the whole (10-egg) clutch.
    expect(find.text('1 egg'), findsNWidgets(6));
    expect(
      find.text('CLUTCH · JUN 1, 2026 – JUN 19, 2026 · 10 EGGS'),
      findsOneWidget,
    );

    // The capped rows must not be the only way in: "Show all" opens the whole
    // ledger in its own scrollable sheet.
    await tester.tap(find.text('Show all (10)'));
    await tester.pumpAndSettle();
    expect(find.text('Egg history'), findsOneWidget);
    // Scoped to the sheet: the capped card is still mounted behind it.
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('1 egg'),
      ),
      findsNWidgets(10),
    );
  });

  testWidgets('no "show all" while the card already shows everything', (
    tester,
  ) async {
    await _pump(
      tester,
      const AnimalLifetime(
        animal: Animal(id: 'a1', species: 'Columba livia'),
        markings: [],
        cases: [],
        accessibleCaseIds: {},
      ),
      eggs: [EggRecord(id: 'e1', animal: 'a1', laidAt: DateTime(2026, 6, 2))],
    );

    expect(find.textContaining('Show all'), findsNothing);
  });

  // One role per test on purpose: `_pump`'s subtree is a const MaterialApp, so
  // pumping it twice in one test lets Flutter reuse the element and the screen
  // never re-reads the new ProviderScope.
  const roleLifetime = AnimalLifetime(
    animal: Animal(id: 'a1', species: 'Columba livia'),
    markings: [],
    cases: [],
    accessibleCaseIds: {},
  );

  testWidgets('a carer sees no destructive overflow', (tester) async {
    await _pump(tester, roleLifetime, role: UserRole.carer);
    expect(find.byType(PopupMenuButton<void>), findsNothing);
  });

  testWidgets('a coordinator sees no destructive overflow', (tester) async {
    await _pump(tester, roleLifetime, role: UserRole.coordinator);
    expect(find.byType(PopupMenuButton<void>), findsNothing);
  });

  testWidgets('a supervisor can reach merge and delete', (tester) async {
    await _pump(tester, roleLifetime, role: UserRole.supervisor);
    await tester.tap(find.byType(PopupMenuButton<void>));
    await tester.pumpAndSettle();
    expect(find.text('Merge duplicate…'), findsOneWidget);
    expect(find.text('Delete animal'), findsOneWidget);
  });

  // Custody gating, both directions (federfall-q7ks.6). One role per test for
  // the const-MaterialApp reason noted above.
  const heldLifetime = AnimalLifetime(
    animal: Animal(id: 'a1', species: 'Columba livia', name: 'Pip'),
    markings: [
      Marking(id: 'm1', animal: 'a1', type: 'mktp_assoc', isActive: true),
    ],
    cases: [],
    accessibleCaseIds: {},
  );

  testWidgets('a holder gets every write control and no read-only badge', (
    tester,
  ) async {
    await _pump(tester, heldLifetime, role: UserRole.carer);

    expect(find.byTooltip('Edit animal'), findsOneWidget);
    expect(find.byTooltip('Add weight'), findsOneWidget);
    expect(find.byTooltip('Add egg laid'), findsOneWidget);
    expect(find.byTooltip('Apply marking'), findsOneWidget);
    expect(find.byTooltip('New case'), findsOneWidget);
    expect(find.byTooltip('Options'), findsOneWidget);
    expect(find.text('Read-only'), findsNothing);
  });

  testWidgets('a non-holder gets none of them, and is told why', (
    tester,
  ) async {
    await _pump(
      tester,
      heldLifetime,
      role: UserRole.carer,
      canWrite: false,
      canOpenCase: false,
    );

    expect(find.byTooltip('Edit animal'), findsNothing);
    expect(find.byTooltip('Add weight'), findsNothing);
    expect(find.byTooltip('Add egg laid'), findsNothing);
    expect(find.byTooltip('Apply marking'), findsNothing);
    expect(find.byTooltip('New case'), findsNothing);
    expect(find.byTooltip('Options'), findsNothing);
    // The record itself still reads — org-wide, for re-identification.
    expect(find.text('Pip'), findsWidgets);
    // The absence is explained rather than mysterious.
    expect(find.text('Read-only'), findsOneWidget);
  });

  // A bird at large is anyone's to admit even though nobody may write about
  // it: that asymmetry is `animalAdmissibleBy` vs `animalWritableBy`, and the
  // screen has to keep the two apart.
  testWidgets('a bird nobody holds can still be admitted', (tester) async {
    await _pump(
      tester,
      heldLifetime,
      role: UserRole.carer,
      canWrite: false,
    );

    expect(find.byTooltip('New case'), findsOneWidget);
    expect(find.byTooltip('Edit animal'), findsNothing);
  });

  testWidgets('a carer holding the bird is still not offered marking delete', (
    tester,
  ) async {
    await _pump(tester, heldLifetime, role: UserRole.carer);
    await tester.tap(find.byTooltip('Options'));
    await tester.pumpAndSettle();

    // `markings.delete` is supervisor-only (1700000010).
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Delete'), findsNothing);
  });
}
