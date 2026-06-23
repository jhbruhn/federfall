import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/features/animals/animals_providers.dart';
import 'package:federfall/features/animals/animals_screen.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

AnimalListItem _item(
  String id, {
  String? name,
  String species = 'Columba livia',
  LifetimeStatus? status,
  List<String> codes = const [],
}) => AnimalListItem(
  animal: Animal(id: id, species: species, name: name, lifetimeStatus: status),
  codes: codes,
);

Future<void> _pump(
  WidgetTester tester, {
  List<AnimalListItem> items = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        animalsRegistryProvider.overrideWith((ref) async => items),
        currentUserProvider.overrideWith((ref) async => null),
      ],
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AnimalsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the empty state with no animals', (tester) async {
    await _pump(tester);
    expect(find.text('No animals yet'), findsOneWidget);
  });

  testWidgets('lists animals with status and codes', (tester) async {
    await _pump(
      tester,
      items: [
        _item(
          'a1',
          name: 'Pip',
          status: LifetimeStatus.inCare,
          codes: const ['DE-1234'],
        ),
      ],
    );

    expect(find.text('Pip'), findsOneWidget);
    expect(find.textContaining('DE-1234'), findsOneWidget);
    expect(find.textContaining('In care'), findsOneWidget);
  });

  testWidgets('search by ring code narrows the list', (tester) async {
    await _pump(
      tester,
      items: [
        _item('a1', name: 'Pip', codes: const ['DE-1234']),
        _item('a2', name: 'Fritz', codes: const ['NL-9999']),
      ],
    );

    await tester.enterText(find.byType(TextField), 'NL-9999');
    await tester.pumpAndSettle();

    expect(find.text('Fritz'), findsOneWidget);
    expect(find.text('Pip'), findsNothing);
  });

  testWidgets('shows no-matches when search excludes all', (tester) async {
    await _pump(tester, items: [_item('a1', name: 'Pip')]);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();

    expect(find.text('No matching animals'), findsOneWidget);
  });
}
