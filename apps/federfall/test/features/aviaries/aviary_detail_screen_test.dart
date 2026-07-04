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
      aviary: const Aviary(id: 'av1', name: 'Garden aviary', capacity: 8),
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
      aviary: const Aviary(id: 'av1', name: 'Garden aviary', capacity: 1),
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
      aviary: const Aviary(id: 'av1', name: 'Quarantine'),
    );
    expect(find.text('No residents'), findsOneWidget);
  });

  testWidgets('edit action only for coordinators/supervisors', (tester) async {
    await _pump(
      tester,
      aviary: const Aviary(id: 'av1', name: 'Garden'),
      user: const AppUser(id: 'u1', email: 'c@x.org', role: UserRole.carer),
    );
    expect(find.byTooltip('Edit aviary'), findsNothing);
  });

  testWidgets('narrow pane keeps Bestand/Pflege behind tabs', (tester) async {
    await _pump(
      tester,
      aviary: const Aviary(id: 'av1', name: 'Garden'),
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
      aviary: const Aviary(id: 'av1', name: 'Garden'),
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
      aviary: const Aviary(id: 'av1', name: 'Garden'),
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
}
