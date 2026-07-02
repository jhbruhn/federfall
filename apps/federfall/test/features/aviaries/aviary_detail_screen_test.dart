import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/features/aviaries/aviaries_providers.dart';
import 'package:federfall/features/aviaries/aviary_detail_screen.dart';
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
  AppUser? user,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        aviaryByIdProvider('av1').overrideWith((ref) async => aviary),
        aviaryResidentsProvider('av1').overrideWith((ref) async => residents),
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
  testWidgets('shows occupancy over capacity and lists residents',
      (tester) async {
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
    await _pump(tester, aviary: const Aviary(id: 'av1', name: 'Quarantine'));
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
}
