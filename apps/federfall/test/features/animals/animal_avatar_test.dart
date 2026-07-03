import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/animals/animal_avatar.dart';
import 'package:federfall/features/animals/animals_providers.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart' hide Finder;
import 'package:mocktail/mocktail.dart';

class MockAnimalsRepo extends Mock implements PbAnimalsRepository {}

Future<void> _pump(
  WidgetTester tester, {
  required Animal animal,
  Uri? thumbUrl,
  Uri? fullUrl,
  PbAnimalsRepository? animals,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        animalByIdProvider('a1').overrideWith((ref) async => animal),
        animalAvatarUrlProvider('a1').overrideWith((ref) async => thumbUrl),
        animalAvatarFullUrlProvider(
          'a1',
        ).overrideWith((ref) async => fullUrl),
        if (animals != null)
          animalsRepositoryProvider.overrideWith((ref) async => animals),
      ],
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: AnimalAvatar(animalId: 'a1', editable: true),
        ),
      ),
    ),
  );
  // Two pumps: one to build, one to let the overridden async providers
  // (animalById, in particular — read synchronously inside _editPhoto)
  // resolve their first value.
  await tester.pump();
  await tester.pump();
}

/// A bounded series of timed pumps: the viewer shows a perpetually-spinning
/// placeholder for images that never resolve in tests, so pumpAndSettle would
/// hang while it's on/off screen.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  const animal = Animal(id: 'a1', species: 'Columba livia', photo: 'p.jpg');

  testWidgets('tapping a photo opens the full-screen viewer at full res', (
    tester,
  ) async {
    await _pump(
      tester,
      animal: animal,
      thumbUrl: Uri.parse('https://example.test/thumb.jpg?thumb=200x200'),
      fullUrl: Uri.parse('https://example.test/full.jpg'),
    );

    await tester.tap(find.byType(InkWell));
    await _settle(tester);

    expect(find.byType(ImageViewerScreen), findsOneWidget);
    final viewer = tester.widget<ImageViewerScreen>(
      find.byType(ImageViewerScreen),
    );
    // The full-res URL is used, not the 200x200 avatar thumbnail.
    expect(viewer.imageUrls, ['https://example.test/full.jpg']);
  });

  testWidgets('tapping with no photo goes straight to the edit sheet', (
    tester,
  ) async {
    const bare = Animal(id: 'a1', species: 'Columba livia');
    final animals = MockAnimalsRepo();
    await _pump(tester, animal: bare, animals: animals);

    await tester.tap(find.byType(InkWell));
    await tester.pumpAndSettle();

    expect(find.byType(ImageViewerScreen), findsNothing);
    expect(find.text('Choose from gallery'), findsOneWidget);
  });

  testWidgets('the viewer edit action reaches the same edit sheet', (
    tester,
  ) async {
    final animals = MockAnimalsRepo();
    await _pump(
      tester,
      animal: animal,
      thumbUrl: Uri.parse('https://example.test/thumb.jpg?thumb=200x200'),
      fullUrl: Uri.parse('https://example.test/full.jpg'),
      animals: animals,
    );

    await tester.tap(find.byType(InkWell));
    await _settle(tester);
    expect(find.byType(ImageViewerScreen), findsOneWidget);

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await _settle(tester);

    expect(find.byType(ImageViewerScreen), findsNothing);
    expect(find.text('Choose from gallery'), findsOneWidget);
  });
}
