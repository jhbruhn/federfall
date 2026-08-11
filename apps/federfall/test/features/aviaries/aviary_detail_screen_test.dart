import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/features/aviaries/aviaries_providers.dart';
import 'package:federfall/features/aviaries/aviary_detail_screen.dart';
import 'package:federfall/features/aviaries/aviary_flock_providers.dart';
import 'package:federfall/features/cases/conditions/conditions_providers.dart';
import 'package:federfall/features/cases/placements/placements_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester, {
  required Aviary aviary,
  List<Animal> residents = const [],
  List<JournalEntry> journal = const [],
  List<AviaryConditionRollupEntry> rollup = const [],
  AppUser? user,
  double? width,
}) async {
  if (width != null) {
    tester.view.physicalSize = Size(width, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        aviaryByIdProvider('av1').overrideWith((ref) async => aviary),
        aviaryResidentsProvider('av1').overrideWith((ref) async => residents),
        aviaryJournalProvider('av1').overrideWith((ref) async => journal),
        aviaryHealthRollupProvider(
          'av1',
        ).overrideWith((ref) async => rollup),
        conditionsByIdProvider.overrideWith((ref) async => const {}),
        orgMembersByIdProvider.overrideWith((ref) async => const {}),
        currentUserProvider.overrideWith((ref) async => user),
      ],
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AviaryDetailScreen(aviaryId: 'av1'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows occupancy over capacity and lists residents', (
    tester,
  ) async {
    await _pump(
      tester,
      aviary: const Aviary(
        id: 'av1',
        keeper: 'u1',
        name: 'Garden aviary',
        capacity: 8,
      ),
      residents: const [
        Animal(id: 'a1', species: 'Columba livia', name: 'Pip'),
        Animal(id: 'a2', species: 'Columba livia'),
      ],
    );

    expect(find.text('Garden aviary'), findsOneWidget);
    expect(find.text('2 / 8'), findsOneWidget); // occupancy chip
    expect(find.text('Pip'), findsOneWidget);
    expect(find.text('Residents'), findsOneWidget);
  });

  testWidgets('over-capacity occupancy chip is highlighted', (tester) async {
    await _pump(
      tester,
      aviary: const Aviary(
        id: 'av1',
        keeper: 'u1',
        name: 'Garden aviary',
        capacity: 1,
      ),
      residents: const [
        Animal(id: 'a1', species: 'Columba livia'),
        Animal(id: 'a2', species: 'Columba livia'),
      ],
    );

    expect(find.text('2 / 1'), findsOneWidget);
    final chip = tester.widget<Chip>(find.byType(Chip));
    final scheme = Theme.of(tester.element(find.byType(Chip))).colorScheme;
    expect(chip.backgroundColor, scheme.errorContainer);
  });

  testWidgets('empty residents state', (tester) async {
    await _pump(
      tester,
      aviary: const Aviary(id: 'av1', keeper: 'u1', name: 'Quarantine'),
    );
    expect(find.text('No residents'), findsOneWidget);
  });

  // 1700000086: the enclosure's own keeper edits it. `keeper` stopped being a
  // label in 1700000076/77 — it is authority over the residents — so the
  // person who answers for the enclosure corrects its own facts.
  group('edit action', () {
    testWidgets('a carer who keeps nothing here does not get it', (
      tester,
    ) async {
      await _pump(
        tester,
        aviary: const Aviary(id: 'av1', keeper: 'keeper', name: 'Garden'),
        user: const AppUser(id: 'u1', email: 'c@x.org', role: UserRole.carer),
      );
      expect(find.byTooltip('Edit aviary'), findsNothing);
    });

    testWidgets("the enclosure's keeper does", (tester) async {
      await _pump(
        tester,
        aviary: const Aviary(id: 'av1', keeper: 'u1', name: 'Garden'),
        user: const AppUser(id: 'u1', email: 'k@x.org', role: UserRole.carer),
      );
      expect(find.byTooltip('Edit aviary'), findsOneWidget);
    });

    testWidgets('a coordinator does, whoever keeps it', (tester) async {
      await _pump(
        tester,
        aviary: const Aviary(id: 'av1', keeper: 'keeper', name: 'Garden'),
        user: const AppUser(
          id: 'u1',
          email: 'c@x.org',
          role: UserRole.coordinator,
        ),
      );
      expect(find.byTooltip('Edit aviary'), findsOneWidget);
    });

    testWidgets('a signed-out session does not', (tester) async {
      await _pump(
        tester,
        aviary: const Aviary(id: 'av1', keeper: 'keeper', name: 'Garden'),
      );
      expect(find.byTooltip('Edit aviary'), findsNothing);
    });
  });

  // The keeper holds every bird in their enclosure, so placing one there is
  // theirs to do — `animals.createRule` has said so since 1700000077 while the
  // FAB was still gated on coordinator+ (federfall-q7ks.6).
  group('add-resident FAB', () {
    testWidgets("the enclosure's keeper may add a resident", (tester) async {
      await _pump(
        tester,
        aviary: const Aviary(id: 'av1', keeper: 'u1', name: 'Garden'),
        user: const AppUser(id: 'u1', email: 'k@x.org', role: UserRole.carer),
      );

      expect(find.text('Add resident'), findsOneWidget);
    });

    testWidgets('another carer may not', (tester) async {
      await _pump(
        tester,
        aviary: const Aviary(id: 'av1', keeper: 'keeper', name: 'Garden'),
        user: const AppUser(id: 'u1', email: 'c@x.org', role: UserRole.carer),
      );

      expect(find.text('Add resident'), findsNothing);
    });

    testWidgets('a coordinator may, whoever keeps it', (tester) async {
      await _pump(
        tester,
        aviary: const Aviary(id: 'av1', keeper: 'keeper', name: 'Garden'),
        user: const AppUser(
          id: 'u1',
          email: 'c@x.org',
          role: UserRole.coordinator,
        ),
      );

      expect(find.text('Add resident'), findsOneWidget);
    });

    testWidgets('a signed-out session may not', (tester) async {
      await _pump(
        tester,
        aviary: const Aviary(id: 'av1', keeper: 'keeper', name: 'Garden'),
      );

      expect(find.text('Add resident'), findsNothing);
    });
  });

  testWidgets('narrow pane keeps Bestand/Pflege behind tabs', (tester) async {
    await _pump(
      tester,
      aviary: const Aviary(id: 'av1', keeper: 'u1', name: 'Garden'),
      user: const AppUser(id: 'u1', email: 'k@x.org', role: UserRole.carer),
      journal: const [
        JournalEntry(id: 'j1', aviary: 'av1', text: 'Cleaned the aviary'),
      ],
      width: 400,
    );

    expect(find.byType(TabBar), findsOneWidget);
    expect(find.text('Stock'), findsOneWidget);
    expect(find.text('Care'), findsOneWidget);
    // Only the Bestand (first) tab's content is initially visible.
    expect(find.text('Residents'), findsOneWidget);
    expect(find.text('Cleaned the aviary'), findsNothing);

    await tester.tap(find.text('Care'));
    await tester.pumpAndSettle();
    expect(find.text('Cleaned the aviary'), findsOneWidget);
  });

  testWidgets('wide pane shows Bestand and Pflege side by side', (
    tester,
  ) async {
    await _pump(
      tester,
      aviary: const Aviary(id: 'av1', keeper: 'u1', name: 'Garden'),
      user: const AppUser(id: 'u1', email: 'k@x.org', role: UserRole.carer),
      residents: const [
        Animal(id: 'a1', species: 'Columba livia', name: 'Pip'),
      ],
      journal: const [
        JournalEntry(id: 'j1', aviary: 'av1', text: 'Cleaned the aviary'),
      ],
      width: 1200,
    );

    expect(find.byType(TabBar), findsNothing);
    expect(find.text('Pip'), findsOneWidget);
    expect(find.text('Cleaned the aviary'), findsOneWidget);
  });

  testWidgets('flock timeline rolls up a condition with a case deep-link', (
    tester,
  ) async {
    await _pump(
      tester,
      aviary: const Aviary(id: 'av1', keeper: 'u1', name: 'Garden'),
      user: const AppUser(id: 'u1', email: 'k@x.org', role: UserRole.carer),
      rollup: const [
        (
          condition: CaseCondition(
            id: 'cc1',
            caseId: 'case1',
            freeText: 'Trichomoniasis',
          ),
          animal: Animal(id: 'a1', species: 'Columba livia', name: 'Pip'),
        ),
      ],
      width: 1200,
    );

    expect(find.text('Trichomoniasis'), findsOneWidget);
    expect(find.text('Pip'), findsWidgets);
    expect(find.byTooltip('Open case record'), findsOneWidget);
  });

  // 1700000089: the flock log is the enclosure's own care record. The tab is
  // ABSENT rather than empty for a non-reader — an "aviary journal" that reads
  // empty for everyone but the keeper is a worse answer than no tab — and its
  // keeper writes it, which used to need a coordinator.
  group('Pflege tab', () {
    const entry = JournalEntry(
      id: 'j1',
      aviary: 'av1',
      text: 'Cleaned the aviary',
    );

    testWidgets('a carer who keeps nothing here gets no tab at all', (
      tester,
    ) async {
      await _pump(
        tester,
        aviary: const Aviary(id: 'av1', keeper: 'keeper', name: 'Garden'),
        user: const AppUser(id: 'u1', email: 'c@x.org', role: UserRole.carer),
        journal: const [entry],
        width: 400,
      );

      expect(find.byType(TabBar), findsNothing);
      expect(find.text('Care'), findsNothing);
      expect(find.text('Cleaned the aviary'), findsNothing);
      // …and Bestand is still theirs to see, without a tab bar over it.
      expect(find.text('Residents'), findsOneWidget);
    });

    testWidgets('nor a second column on a wide pane', (tester) async {
      await _pump(
        tester,
        aviary: const Aviary(id: 'av1', keeper: 'keeper', name: 'Garden'),
        user: const AppUser(id: 'u1', email: 'c@x.org', role: UserRole.carer),
        journal: const [entry],
        width: 1200,
      );

      expect(find.text('Cleaned the aviary'), findsNothing);
      expect(find.byType(VerticalDivider), findsNothing);
      expect(find.text('Residents'), findsOneWidget);
    });

    testWidgets("the enclosure's keeper reads it and may write", (
      tester,
    ) async {
      await _pump(
        tester,
        aviary: const Aviary(id: 'av1', keeper: 'u1', name: 'Garden'),
        user: const AppUser(id: 'u1', email: 'k@x.org', role: UserRole.carer),
        journal: const [entry],
        width: 1200,
      );

      expect(find.text('Cleaned the aviary'), findsOneWidget);
      expect(find.text('Entry'), findsOneWidget); // add-entry FAB
    });

    testWidgets('a coordinator does, whoever keeps it', (tester) async {
      await _pump(
        tester,
        aviary: const Aviary(id: 'av1', keeper: 'keeper', name: 'Garden'),
        user: const AppUser(
          id: 'u1',
          email: 'c@x.org',
          role: UserRole.coordinator,
        ),
        journal: const [entry],
        width: 1200,
      );

      expect(find.text('Cleaned the aviary'), findsOneWidget);
      expect(find.text('Entry'), findsOneWidget);
    });

    testWidgets('a signed-out session does not', (tester) async {
      await _pump(
        tester,
        aviary: const Aviary(id: 'av1', keeper: 'keeper', name: 'Garden'),
        journal: const [entry],
        width: 1200,
      );

      expect(find.text('Cleaned the aviary'), findsNothing);
    });
  });
}
