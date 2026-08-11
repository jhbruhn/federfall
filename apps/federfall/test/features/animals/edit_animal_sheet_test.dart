import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/animals/edit_animal_sheet.dart';
import 'package:federfall/features/animals/species_field.dart';
import 'package:federfall/features/cases/animal_species_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart' hide Finder;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAnimalsRepo extends Mock implements PbAnimalsRepository {}

void main() {
  setUpAll(() => registerFallbackValue(<String, dynamic>{}));

  const animal = Animal(id: 'a1', species: 'Stadttaube', name: 'Hedwig');

  late MockAnimalsRepo animals;
  late Map<String, dynamic> saved;

  setUp(() {
    animals = MockAnimalsRepo();
    saved = {};
    when(() => animals.update(any(), any())).thenAnswer((inv) async {
      saved = inv.positionalArguments[1] as Map<String, dynamic>;
      return animal;
    });
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          animalsRepositoryProvider.overrideWith((ref) async => animals),
          animalSpeciesProvider.overrideWith(
            (ref) async => const ['Ringeltaube', 'Stadttaube'],
          ),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showEditAnimalSheet(context, animal),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Finder speciesInput() => find.descendant(
    of: find.byType(SpeciesField),
    matching: find.byType(TextField),
  );

  testWidgets('opens on the animals own species', (tester) async {
    await pump(tester);
    final field = tester.widget<TextField>(speciesInput());
    expect(field.controller?.text, 'Stadttaube');
  });

  testWidgets('corrects the species from the org vocabulary', (tester) async {
    await pump(tester);
    await tester.tap(speciesInput());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ringeltaube').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    verify(() => animals.update('a1', any())).called(1);
    expect(saved['species'], 'Ringeltaube');
  });

  testWidgets('refuses to save an emptied species', (tester) async {
    await pump(tester);
    await tester.enterText(speciesInput(), '');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    verifyNever(() => animals.update(any(), any()));
    expect(find.text('This field is required'), findsOneWidget);
  });
}
