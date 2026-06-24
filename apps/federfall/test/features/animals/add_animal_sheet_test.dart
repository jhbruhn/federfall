import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/animals/add_animal_sheet.dart';
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

  late MockAnimalsRepo animals;
  late Map<String, dynamic> created;

  setUp(() {
    animals = MockAnimalsRepo();
    created = {};
    when(() => animals.create(any())).thenAnswer((inv) async {
      created = inv.positionalArguments.first as Map<String, dynamic>;
      return const Animal(id: 'new1', species: 'Stadttaube');
    });
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          animalsRepositoryProvider.overrideWith((ref) async => animals),
          currentUserProvider.overrideWith(
            (ref) async =>
                const AppUser(id: 'u1', email: 'a@x.org', org: 'org1'),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showAddAnimalSheet(context, aviaryId: 'av1'),
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

  testWidgets('adds a resident animal placed in the aviary', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextFormField).first, 'Stadttaube');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    verify(() => animals.create(any())).called(1);
    expect(created['species'], 'Stadttaube');
    expect(created['org'], 'org1');
    expect(created['current_aviary'], 'av1');
    expect(created['lifetime_status'], LifetimeStatus.inAviary.wire);
  });
}
