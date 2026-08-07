import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/features/animals/animals_providers.dart';
import 'package:federfall/features/animals/animals_screen.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Longer than the search field's debounce. `pumpAndSettle` alone would not
/// get there: a pending Timer schedules no frame, so it stops before the
/// debounce elapses.
const _pastDebounce = Duration(milliseconds: 400);

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

/// The registry's search is a server query now (federfall-trep), so the fake
/// feed answers per search term and the test asserts the screen asked the
/// right one — the matching itself is the repository's, and tested there.
class _FakeFeed extends AnimalRegistryFeed {
  _FakeFeed(this.itemsFor);

  final List<AnimalListItem> Function(String search) itemsFor;

  @override
  Future<AnimalRegistryState> build(String search) async =>
      AnimalRegistryState(items: itemsFor(search));
}

Future<void> _pump(
  WidgetTester tester, {
  List<AnimalListItem> items = const [],
  List<AnimalListItem> Function(String search)? itemsFor,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        animalRegistryFeedProvider.overrideWith2(
          (_) => _FakeFeed(itemsFor ?? (_) => items),
        ),
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

  testWidgets('search by ring code re-asks and narrows the list', (
    tester,
  ) async {
    final asked = <String>[];
    await _pump(
      tester,
      itemsFor: (search) {
        asked.add(search);
        return search.isEmpty
            ? [_item('a1', name: 'Pip'), _item('a2', name: 'Fritz')]
            : [
                _item('a2', name: 'Fritz', codes: const ['NL-9999']),
              ];
      },
    );

    await tester.enterText(find.byType(TextField), 'NL-9999');
    await tester.pump();
    // Debounced, so a typed code is one request rather than seven.
    expect(asked, ['']);

    await tester.pump(_pastDebounce);
    await tester.pumpAndSettle();

    expect(asked.last, 'NL-9999');
    expect(find.text('Fritz'), findsOneWidget);
    expect(find.text('Pip'), findsNothing);
  });

  testWidgets('shows no-matches when the search finds nothing', (tester) async {
    // Which emptiness this is can no longer be read off the loaded rows — an
    // active search term is what says it.
    await _pump(
      tester,
      itemsFor: (search) =>
          search.isEmpty ? [_item('a1', name: 'Pip')] : const [],
    );

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump(_pastDebounce);
    await tester.pumpAndSettle();

    expect(find.text('No matching animals'), findsOneWidget);
    expect(find.text('No animals yet'), findsNothing);
  });
}
