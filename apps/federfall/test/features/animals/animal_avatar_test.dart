import 'dart:async';

import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/animals/animal_avatar.dart';
import 'package:federfall/features/animals/animals_providers.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/features/cases/journal/journal_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart' hide Finder;
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:mocktail/mocktail.dart';

class MockAnimalsRepo extends Mock implements PbAnimalsRepository {}

class MockImagePicker extends Mock implements ImagePicker {}

Future<void> _pump(
  WidgetTester tester, {
  required Animal animal,
  Uri? thumbUrl,
  Uri? fullUrl,
  PbAnimalsRepository? animals,
  ImagePicker? picker,
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
        if (picker != null) imagePickerProvider.overrideWithValue(picker),
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

/// Alternates real-async progress with frame pumps until [done], or gives up.
///
/// The crop step hands its pixel work to a background isolate, which a widget
/// test's fake clock does not drive — only `runAsync` does — while the route
/// transition around it needs ordinary pumps, and `pump` may not be called
/// from inside `runAsync`. Interleaving is what lets both finish.
Future<void> _settleAsync(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 60 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
}

void main() {
  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(<http.MultipartFile>[]);
    registerFallbackValue(ImageSource.gallery);
  });

  const animal = Animal(id: 'a1', species: 'Columba livia', photo: 'p.jpg');
  const bare = Animal(id: 'a1', species: 'Columba livia');

  /// A real, decodable JPEG — the crop screen decodes what it is handed, so
  /// the usual fake bytes would never get past its loading placeholder.
  final photoBytes = img.encodeJpg(img.Image(width: 40, height: 40));

  /// A picker that always returns [photoBytes] under a non-JPEG name, so the
  /// re-encode's effect on the upload filename is visible.
  MockImagePicker pickerReturningPhoto() {
    final picker = MockImagePicker();
    when(
      () => picker.pickImage(source: any(named: 'source')),
    ).thenAnswer((_) async => XFile.fromData(photoBytes, name: 'shot.png'));
    return picker;
  }

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

  testWidgets('a picked photo goes through the crop step before upload', (
    tester,
  ) async {
    final animals = MockAnimalsRepo();
    await _pump(
      tester,
      animal: bare,
      animals: animals,
      picker: pickerReturningPhoto(),
    );

    await tester.tap(find.byType(InkWell));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose from gallery'));
    await _settle(tester);

    expect(find.byType(ImageCropScreen), findsOneWidget);
    // Nothing is uploaded until the crop is confirmed.
    verifyNever(() => animals.updateWithFiles(any(), any(), any()));
  });

  testWidgets('backing out of the crop leaves the photo unchanged', (
    tester,
  ) async {
    final animals = MockAnimalsRepo();
    await _pump(
      tester,
      animal: bare,
      animals: animals,
      picker: pickerReturningPhoto(),
    );

    await tester.tap(find.byType(InkWell));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose from gallery'));
    await _settle(tester);

    // A fullscreen dialog's leading affordance is Close, not Back.
    await tester.tap(find.byTooltip('Close'));
    await _settle(tester);

    expect(find.byType(ImageCropScreen), findsNothing);
    verifyNever(() => animals.updateWithFiles(any(), any(), any()));
  });

  testWidgets('confirming the crop uploads the cropped JPEG', (tester) async {
    final animals = MockAnimalsRepo();
    final uploaded = Completer<List<http.MultipartFile>>();
    when(() => animals.updateWithFiles(any(), any(), any())).thenAnswer((
      invocation,
    ) async {
      uploaded.complete(
        invocation.positionalArguments[2] as List<http.MultipartFile>,
      );
      return bare;
    });
    await _pump(
      tester,
      animal: bare,
      animals: animals,
      picker: pickerReturningPhoto(),
    );

    await tester.tap(find.byType(InkWell));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose from gallery'));
    await _settle(tester);
    await tester.tap(find.text('Save'));
    await _settleAsync(tester, () => uploaded.isCompleted);

    final files = await uploaded.future;
    expect(files.single.field, 'photo');
    // Re-encoded as JPEG, so a non-JPEG name must not survive. (`XFile.name`
    // is empty under test, so this is the fallback stem — the extension is
    // what this pins.)
    expect(files.single.filename, endsWith('.jpg'));
    expect(files.single.length, greaterThan(0));
  });
}
