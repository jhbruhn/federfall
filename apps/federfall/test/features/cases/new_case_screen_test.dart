import 'dart:async';
import 'dart:typed_data';

import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/journal/journal_providers.dart';
import 'package:federfall/features/cases/new_case_screen.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart' hide Finder;
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:mocktail/mocktail.dart';

class MockAnimalsRepo extends Mock implements PbAnimalsRepository {}

class MockCasesRepo extends Mock implements PbCasesRepository {}

class MockFindersRepo extends Mock implements PbFindersRepository {}

class MockMarkingsRepo extends Mock implements PbMarkingsRepository {}

class MockImagePicker extends Mock implements ImagePicker {}

void main() {
  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(<http.MultipartFile>[]);
  });

  late MockAnimalsRepo animals;
  late MockCasesRepo cases;
  late MockFindersRepo finders;
  late MockMarkingsRepo markings;
  late MockImagePicker picker;

  setUp(() {
    animals = MockAnimalsRepo();
    cases = MockCasesRepo();
    finders = MockFindersRepo();
    markings = MockMarkingsRepo();
    picker = MockImagePicker();
    when(picker.pickMultiImage).thenAnswer((_) async => []);
    when(() => animals.create(any()))
        .thenAnswer((_) async => const Animal(id: 'a1', species: 'Stadttaube'));
    when(() => animals.searchByName(any())).thenAnswer((_) async => []);
    when(() => cases.create(any()))
        .thenAnswer((_) async => const Case(id: 'c1', animal: 'a1'));
    when(() => cases.forAnimal(any())).thenAnswer((_) async => []);
    when(() => finders.create(any()))
        .thenAnswer((_) async => const Finder(id: 'f1'));
    when(() => markings.activeByCode(any())).thenAnswer((_) async => []);
    when(() => markings.forAnimal(any())).thenAnswer((_) async => []);
  });

  // Enters [value] into the field carrying [label], located via its label text.
  Future<void> enterByLabel(
    WidgetTester tester,
    String label,
    String value,
  ) async {
    final field = find.ancestor(
      of: find.text(label),
      matching: find.byType(TextField),
    );
    await tester.enterText(field, value);
  }

  Future<void> pump(WidgetTester tester, {String? animalId}) async {
    final container = ProviderContainer(
      overrides: [
        currentUserProvider.overrideWith(
          (ref) async =>
              const AppUser(id: 'u1', email: 'me@x.org', org: 'org1'),
        ),
        animalsRepositoryProvider.overrideWith((ref) async => animals),
        casesRepositoryProvider.overrideWith((ref) async => cases),
        findersRepositoryProvider.overrideWith((ref) async => finders),
        markingsRepositoryProvider.overrideWith((ref) async => markings),
        imagePickerProvider.overrideWithValue(picker),
      ],
    );
    addTearDown(container.dispose);

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('HOME')),
        ),
        GoRoute(
          path: '/cases/new',
          builder: (_, state) =>
              NewCaseScreen(animalId: state.uri.queryParameters['animal']),
        ),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    unawaited(
      router.push(
        animalId == null ? '/cases/new' : '/cases/new?animal=$animalId',
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('creates an animal + case and returns to the list',
      (tester) async {
    await pump(tester);

    // Pick a reason (species is pre-filled with the default).
    await tester.tap(find.widgetWithText(FilterChip, 'Injury'));
    await tester.pumpAndSettle();

    final submit = find.widgetWithText(FilledButton, 'Create case');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    final animalBody =
        verify(() => animals.create(captureAny())).captured.single
            as Map<String, dynamic>;
    expect(animalBody['species'], 'Stadttaube');
    expect(animalBody['org'], 'org1');

    final caseBody = verify(() => cases.create(captureAny())).captured.single
        as Map<String, dynamic>;
    expect(caseBody['animal'], 'a1');
    expect(caseBody['org'], 'org1');
    expect(caseBody['active_carer'], 'u1');
    expect(caseBody['reasons_for_admission'], ['injury']);

    // Popped back to the list.
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('requires a reason before submitting', (tester) async {
    await pump(tester);

    final submit = find.widgetWithText(FilledButton, 'Create case');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    verifyNever(() => animals.create(any()));
    expect(find.text('This field is required'), findsOneWidget);
  });

  testWidgets('captures intake details and creates a linked finder',
      (tester) async {
    await pump(tester);

    await enterByLabel(tester, 'Intake weight (g)', '250');
    await enterByLabel(tester, 'Intake notes', 'thin but alert');
    await enterByLabel(tester, 'Find location', 'Domplatz');

    // Open the optional finder section and fill some contact details.
    final finderHeader = find.text('Finder (optional)');
    await tester.ensureVisible(finderHeader);
    await tester.tap(finderHeader);
    await tester.pumpAndSettle();
    await enterByLabel(tester, 'Last name', 'Klein');
    await enterByLabel(tester, 'Phone', '0151 234');

    final injury = find.widgetWithText(FilterChip, 'Injury');
    await tester.ensureVisible(injury);
    await tester.tap(injury);
    await tester.pumpAndSettle();

    final submit = find.widgetWithText(FilledButton, 'Create case');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    final caseBody = verify(() => cases.create(captureAny())).captured.single
        as Map<String, dynamic>;
    expect(caseBody['intake_weight_g'], 250);
    expect(caseBody['intake_notes'], 'thin but alert');
    expect(caseBody['find_location'], 'Domplatz');
    expect(caseBody['finder'], 'f1');

    final finderBody = verify(() => finders.create(captureAny()))
        .captured
        .single as Map<String, dynamic>;
    expect(finderBody['last_name'], 'Klein');
    expect(finderBody['phone'], '0151 234');
    expect(finderBody['org'], 'org1');
  });

  testWidgets('does not create a finder when the section is left blank',
      (tester) async {
    await pump(tester);

    final injury = find.widgetWithText(FilterChip, 'Injury');
    await tester.ensureVisible(injury);
    await tester.tap(injury);
    await tester.pumpAndSettle();

    final submit = find.widgetWithText(FilledButton, 'Create case');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    verifyNever(() => finders.create(any()));
    final caseBody = verify(() => cases.create(captureAny())).captured.single
        as Map<String, dynamic>;
    expect(caseBody.containsKey('finder'), isFalse);
  });

  testWidgets('re-identifying links the case to the existing animal',
      (tester) async {
    when(() => animals.searchByName('Pauli')).thenAnswer(
      (_) async =>
          const [Animal(id: 'a9', species: 'Stadttaube', name: 'Pauli')],
    );

    await pump(tester);

    // Search for a returning bird and link the match.
    await enterByLabel(tester, 'Returning bird? Search', 'Pauli');
    await tester.tap(find.byIcon(Icons.search).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pauli · Stadttaube'));
    await tester.pumpAndSettle();

    // Linked summary is shown; the create-animal fields are gone.
    expect(find.byIcon(Icons.link), findsOneWidget);

    final injury = find.widgetWithText(FilterChip, 'Injury');
    await tester.ensureVisible(injury);
    await tester.tap(injury);
    await tester.pumpAndSettle();

    final submit = find.widgetWithText(FilledButton, 'Create case');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    verifyNever(() => animals.create(any()));
    final caseBody = verify(() => cases.create(captureAny())).captured.single
        as Map<String, dynamic>;
    expect(caseBody['animal'], 'a9');
  });

  testWidgets('pre-links the case when opened for an existing animal',
      (tester) async {
    when(() => animals.getOne('a1')).thenAnswer(
      (_) async => const Animal(id: 'a1', species: 'Stadttaube', name: 'Pauli'),
    );

    await pump(tester, animalId: 'a1');

    // The animal is pre-linked (linked summary shown, no re-id search).
    expect(find.byIcon(Icons.link), findsOneWidget);
    expect(find.text('Returning bird? Search'), findsNothing);

    final injury = find.widgetWithText(FilterChip, 'Injury');
    await tester.ensureVisible(injury);
    await tester.tap(injury);
    await tester.pumpAndSettle();

    final submit = find.widgetWithText(FilledButton, 'Create case');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    verifyNever(() => animals.create(any()));
    final caseBody = verify(() => cases.create(captureAny())).captured.single
        as Map<String, dynamic>;
    expect(caseBody['animal'], 'a1');
  });

  testWidgets('staged intake photos upload via createWithFiles',
      (tester) async {
    when(picker.pickMultiImage).thenAnswer(
      (_) async => [
        XFile.fromData(
          Uint8List.fromList([1, 2, 3]),
          name: 'intake.jpg',
          mimeType: 'image/jpeg',
        ),
      ],
    );
    when(() => cases.createWithFiles(any(), any()))
        .thenAnswer((_) async => const Case(id: 'c1', animal: 'a1'));

    await pump(tester);

    final addPhotos = find.widgetWithText(OutlinedButton, 'Add photos');
    await tester.ensureVisible(addPhotos);
    await tester.tap(addPhotos);
    await tester.pumpAndSettle();

    final injury = find.widgetWithText(FilterChip, 'Injury');
    await tester.ensureVisible(injury);
    await tester.tap(injury);
    await tester.pumpAndSettle();

    final submit = find.widgetWithText(FilledButton, 'Create case');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    verifyNever(() => cases.create(any()));
    final files = verify(
      () => cases.createWithFiles(any(), captureAny()),
    ).captured.single as List<http.MultipartFile>;
    expect(files.length, 1);
    expect(files.single.field, 'intake_photos');
  });
}
