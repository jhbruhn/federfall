import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/features/aviaries/aviaries_providers.dart';
import 'package:federfall/features/aviaries/aviaries_screen.dart';
import 'package:federfall/features/cases/placements/placements_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester, {
  List<Aviary> aviaries = const [],
  Map<String, int> occupancy = const {},
  AppUser? user,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        aviariesProvider.overrideWith((ref) async => aviaries),
        aviaryOccupancyCountsProvider.overrideWith((ref) async => occupancy),
        orgMembersByIdProvider.overrideWith((ref) async => const {}),
        currentUserProvider.overrideWith((ref) async => user),
      ],
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AviariesScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists aviaries with occupancy and inactive badge',
      (tester) async {
    await _pump(
      tester,
      aviaries: const [
        Aviary(id: 'av1', name: 'Garden aviary', capacity: 8),
        Aviary(id: 'av2', name: 'Quarantine pen', active: false),
      ],
      occupancy: const {'av1': 3},
    );

    expect(find.text('Garden aviary'), findsOneWidget);
    expect(find.textContaining('3 / 8'), findsOneWidget);
    expect(find.textContaining('Inactive'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsNothing);
  });

  testWidgets('an over-capacity aviary is flagged in the list',
      (tester) async {
    await _pump(
      tester,
      aviaries: const [Aviary(id: 'av1', name: 'Garden aviary', capacity: 8)],
      occupancy: const {'av1': 9},
    );

    expect(find.textContaining('9 / 8'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });

  testWidgets('empty state when there are no aviaries', (tester) async {
    await _pump(tester);
    expect(find.text('No aviaries yet'), findsOneWidget);
  });

  testWidgets('a carer does not see the create FAB', (tester) async {
    await _pump(
      tester,
      aviaries: const [Aviary(id: 'av1', name: 'Garden aviary')],
      user: const AppUser(id: 'u1', email: 'c@x.org', role: UserRole.carer),
    );
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('a coordinator sees the create FAB when aviaries exist',
      (tester) async {
    await _pump(
      tester,
      aviaries: const [Aviary(id: 'av1', name: 'Garden aviary')],
      user: const AppUser(
        id: 'u2',
        email: 's@x.org',
        role: UserRole.coordinator,
      ),
    );
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });

  testWidgets('a coordinator on an empty list gets the CTA, not the FAB',
      (tester) async {
    await _pump(
      tester,
      user: const AppUser(
        id: 'u2',
        email: 's@x.org',
        role: UserRole.coordinator,
      ),
    );
    // The empty-state CTA replaces the FAB to avoid two identical actions.
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.widgetWithText(FilledButton, 'New aviary'), findsOneWidget);
  });
}
