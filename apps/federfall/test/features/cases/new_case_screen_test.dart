import 'dart:async';
import 'dart:typed_data';

import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/admission_reasons_providers.dart';
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

class MockMarkingsRepo extends Mock implements PbMarkingsRepository {}

class MockImagePicker extends Mock implements ImagePicker {}

void main() {
  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(<http.MultipartFile>[]);
  });

  late MockAnimalsRepo animals;
  late MockCasesRepo cases;
  late MockMarkingsRepo markings;
  late MockImagePicker picker;

  setUp(() {
    animals = MockAnimalsRepo();
    cases = MockCasesRepo();
    markings = MockMarkingsRepo();
    picker = MockImagePicker();
    when(picker.pickMultiImage).thenAnswer((_) async => []);
    when(() => animals.searchByName(any())).thenAnswer((_) async => []);
    // The whole intake is one atomic backend call (federfall-zod).
    when(() => cases.intake(any(), photos: any(named: 'photos')))
        .thenAnswer((_) async => (caseId: 'c1', animalId: 'a1'));
    when(() => cases.forAnimal(any())).thenAnswer((_) async => []);
    when(() => markings.activeByCode(any())).thenAnswer((_) async => []);
    when(() => markings.forAnimal(any())).thenAnswer((_) async => []);
  });

  // The payload of the single intake call.
  Map<String, dynamic> capturedPayload() =>
      verify(() => cases.intake(captureAny(), photos: any(named: 'photos')))
          .captured
          .single as Map<String, dynamic>;

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

  // Advances the intake wizard to the next step.
  Future<void> tapNext(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Next'));
    await tester.pumpAndSettle();
  }

  Future<void> pump(WidgetTester tester, {String? animalId}) async {
    // A tall surface so each wizard step lays out without scrolling.
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [
        currentUserProvider.overrideWith(
          (ref) async =>
              const AppUser(id: 'u1', email: 'me@x.org', org: 'org1'),
        ),
        animalsRepositoryProvider.overrideWith((ref) async => animals),
        admissionReasonsProvider.overrideWith(
          (ref) async => const [AdmissionReason(id: 'adre1', label: 'Injury')],
        ),
        casesRepositoryProvider.overrideWith((ref) async => cases),
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
        // Stand-in for the real case detail: after intake the wizard
        // navigates here instead of popping back to the list.
        GoRoute(
          path: '/cases/:id',
          builder: (_, state) =>
              Scaffold(body: Text('CASE ${state.pathParameters['id']}')),
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

  // Picks the Injury reason on the intake (step 1) — the required field.
  Future<void> pickInjury(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilterChip, 'Injury'));
    await tester.pumpAndSettle();
  }

  testWidgets('submits one atomic intake and opens the created case',
      (tester) async {
    await pump(tester);

    // Step 0 (species pre-filled) → step 1: pick a reason → step 2: create.
    await tapNext(tester);
    await pickInjury(tester);
    await tapNext(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Create case'));
    await tester.pumpAndSettle();

    final payload = capturedPayload();
    expect(payload['species'], 'Stadttaube');
    // org / active_carer come from the authenticated session server-side.
    expect(payload.containsKey('org'), isFalse);
    expect(payload.containsKey('active_carer'), isFalse);
    final caseBody = payload['case'] as Map<String, dynamic>;
    expect(caseBody['admission_reasons'], ['adre1']);

    // Landed on the case just admitted, not back on the list.
    expect(find.text('CASE c1'), findsOneWidget);
    expect(find.text('HOME'), findsNothing);
  });

  testWidgets('opens the exam sheet after intake when opted in',
      (tester) async {
    await pump(tester);

    await tapNext(tester);
    await pickInjury(tester);
    await tapNext(tester);

    final toggle = find.widgetWithText(SwitchListTile, 'Record an exam now');
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Create case'));
    // The create button keeps spinning while the awaited sheet is open, so
    // pump explicit frames rather than settling.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // The case was created, and the exam sheet opened on it instead of
    // popping straight back to the list.
    verify(() => cases.intake(any(), photos: any(named: 'photos'))).called(1);
    expect(find.text('New exam'), findsOneWidget);
    expect(find.text('HOME'), findsNothing);
  });

  testWidgets('requires a reason before advancing past intake',
      (tester) async {
    await pump(tester);

    await tapNext(tester); // step 0 → 1
    // Try to advance without a reason: stays on step 1 with an error.
    await tapNext(tester);

    expect(find.text('This field is required'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Create case'), findsNothing);
    verifyNever(() => cases.intake(any(), photos: any(named: 'photos')));
  });

  testWidgets('captures intake details, weight and finder in the payload',
      (tester) async {
    await pump(tester);

    await tapNext(tester); // step 0 → 1

    await pickInjury(tester);
    await enterByLabel(tester, 'Intake weight (g)', '250');
    await enterByLabel(tester, 'Find location', 'Domplatz');

    await tapNext(tester); // step 1 → 2

    await enterByLabel(tester, 'Intake notes', 'thin but alert');
    // Open the optional finder section and fill some contact details.
    await tester.tap(find.text('Finder (optional)'));
    await tester.pumpAndSettle();
    await enterByLabel(tester, 'Last name', 'Klein');
    await enterByLabel(tester, 'Phone', '0151 234');

    await tester.tap(find.widgetWithText(FilledButton, 'Create case'));
    await tester.pumpAndSettle();

    final payload = capturedPayload();
    final caseBody = payload['case'] as Map<String, dynamic>;
    expect(caseBody['intake_notes'], 'thin but alert');
    expect(caseBody['find_location'], 'Domplatz');

    // Intake weight travels with the intake (a Weight row server-side).
    expect(payload['weight_g'], 250);

    final finderBody = payload['finder'] as Map<String, dynamic>;
    expect(finderBody['last_name'], 'Klein');
    expect(finderBody['phone'], '0151 234');
  });

  testWidgets('omits the finder when the section is left blank',
      (tester) async {
    await pump(tester);

    await tapNext(tester);
    await pickInjury(tester);
    await tapNext(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Create case'));
    await tester.pumpAndSettle();

    final payload = capturedPayload();
    expect(payload.containsKey('finder'), isFalse);
    expect(payload.containsKey('weight_g'), isFalse);
  });

  testWidgets('re-identifying links the case to the existing animal',
      (tester) async {
    when(() => animals.searchByName('Pauli')).thenAnswer(
      (_) async =>
          const [Animal(id: 'a9', species: 'Stadttaube', name: 'Pauli')],
    );
    when(() => cases.intake(any(), photos: any(named: 'photos')))
        .thenAnswer((_) async => (caseId: 'c1', animalId: 'a9'));

    await pump(tester);

    // Step 0: search for a returning bird and link the match.
    await enterByLabel(tester, 'Returning bird? Search', 'Pauli');
    await tester.tap(find.byIcon(Icons.search).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pauli · Stadttaube'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.link), findsOneWidget);

    await tapNext(tester); // step 0 → 1 (linked, no species needed)
    await pickInjury(tester);
    await tapNext(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Create case'));
    await tester.pumpAndSettle();

    final payload = capturedPayload();
    expect(payload['animal'], 'a9');
    expect(payload.containsKey('species'), isFalse);
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

    await tapNext(tester);
    await pickInjury(tester);
    await tapNext(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Create case'));
    await tester.pumpAndSettle();

    final payload = capturedPayload();
    expect(payload['animal'], 'a1');
    expect(payload.containsKey('species'), isFalse);
  });

  testWidgets('leaving a pristine wizard pops without prompting',
      (tester) async {
    await pump(tester);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Discard changes?'), findsNothing);
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('back mid-intake asks before discarding the input',
      (tester) async {
    await pump(tester);

    // Any input marks the wizard dirty — here the animal's name. Pump so the
    // markDirty setState rebuilds PopScope.canPop before the back gesture.
    await enterByLabel(tester, 'Name (optional)', 'Pauli');
    await tester.pump();
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Keep editing: the wizard (with the input) stays.
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('HOME'), findsNothing);
    expect(find.text('Pauli'), findsOneWidget);

    // Discard: back to the list, nothing created.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('HOME'), findsOneWidget);
    verifyNever(() => cases.intake(any(), photos: any(named: 'photos')));
  });

  testWidgets('progress without typing still guards against back',
      (tester) async {
    await pump(tester);

    // Advancing needs a picked reason chip — non-text input must also count
    // as unsaved progress.
    await tapNext(tester);
    await pickInjury(tester);
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Discard changes?'), findsOneWidget);
  });

  testWidgets('staged intake photos ride along on the intake call',
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

    await pump(tester);

    await tapNext(tester);
    await pickInjury(tester);
    await tapNext(tester); // step 2 — photos live here

    await tester.tap(find.widgetWithText(OutlinedButton, 'Add photos'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Create case'));
    await tester.pumpAndSettle();

    final files = verify(
      () => cases.intake(any(), photos: captureAny(named: 'photos')),
    ).captured.single as List<http.MultipartFile>;
    expect(files.length, 1);
    expect(files.single.field, 'intake_photos');
  });
}
