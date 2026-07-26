import 'dart:async';
import 'dart:typed_data';

import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/admission_reasons_providers.dart';
import 'package:federfall/features/cases/case_intake_draft.dart';
import 'package:federfall/features/cases/case_intake_draft_store.dart';
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

import '../../helpers/helpers.dart';

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
  late FakeCaseIntakeDraftStore drafts;
  late FakeStagedPhotoLoader photoLoader;

  setUp(() {
    animals = MockAnimalsRepo();
    drafts = FakeCaseIntakeDraftStore();
    photoLoader = FakeStagedPhotoLoader(const {});
    cases = MockCasesRepo();
    markings = MockMarkingsRepo();
    picker = MockImagePicker();
    when(picker.pickMultiImage).thenAnswer((_) async => []);
    when(() => animals.searchByName(any())).thenAnswer((_) async => []);
    // The whole intake is one atomic backend call (federfall-zod).
    when(
      () => cases.intake(
        any(),
        photos: any(named: 'photos'),
        idempotencyKey: any(named: 'idempotencyKey'),
      ),
    ).thenAnswer((_) async => (caseId: 'c1', animalId: 'a1'));
    when(() => cases.forAnimal(any())).thenAnswer((_) async => []);
    when(() => markings.activeByCode(any())).thenAnswer((_) async => []);
    when(() => markings.forAnimal(any())).thenAnswer((_) async => []);
  });

  // The payload of the single intake call.
  Map<String, dynamic> capturedPayload() =>
      verify(
            () => cases.intake(
              captureAny(),
              photos: any(named: 'photos'),
              idempotencyKey: any(named: 'idempotencyKey'),
            ),
          ).captured.single
          as Map<String, dynamic>;

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
        // The real store reads the platform keystore, which never answers
        // under `flutter test`.
        caseIntakeDraftStoreProvider.overrideWithValue(drafts),
        stagedPhotoLoaderProvider.overrideWithValue(photoLoader),
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

  testWidgets('submits one atomic intake and opens the created case', (
    tester,
  ) async {
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

  testWidgets('a retry after a failure resubmits the SAME idempotency key', (
    tester,
  ) async {
    // First submit times out (the intake may still have committed
    // server-side), the second succeeds — the backend can only dedupe the
    // pair when both carry one identical key (federfall-3ty3).
    var calls = 0;
    when(
      () => cases.intake(
        any(),
        photos: any(named: 'photos'),
        idempotencyKey: any(named: 'idempotencyKey'),
      ),
    ).thenAnswer((_) async {
      calls++;
      if (calls == 1) {
        throw const RepositoryException(
          'timeout',
          kind: RepositoryErrorKind.network,
        );
      }
      return (caseId: 'c1', animalId: 'a1');
    });

    await pump(tester);
    await tapNext(tester);
    await pickInjury(tester);
    await tapNext(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Create case'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Create case'));
    await tester.pumpAndSettle();

    final keys = verify(
      () => cases.intake(
        any(),
        photos: any(named: 'photos'),
        idempotencyKey: captureAny(named: 'idempotencyKey'),
      ),
    ).captured.cast<String>();
    expect(keys, hasLength(2));
    expect(keys.first, isNotEmpty);
    expect(keys.first, keys.last);
  });

  testWidgets('opens the exam sheet after intake when opted in', (
    tester,
  ) async {
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
    verify(
      () => cases.intake(
        any(),
        photos: any(named: 'photos'),
        idempotencyKey: any(named: 'idempotencyKey'),
      ),
    ).called(1);
    expect(find.text('New exam'), findsOneWidget);
    expect(find.text('HOME'), findsNothing);
  });

  testWidgets('requires a reason before advancing past intake', (tester) async {
    await pump(tester);

    await tapNext(tester); // step 0 → 1
    // Try to advance without a reason: stays on step 1 with an error.
    await tapNext(tester);

    expect(find.text('This field is required'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Create case'), findsNothing);
    verifyNever(
      () => cases.intake(
        any(),
        photos: any(named: 'photos'),
        idempotencyKey: any(named: 'idempotencyKey'),
      ),
    );
  });

  testWidgets('captures intake details, weight and finder in the payload', (
    tester,
  ) async {
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

  testWidgets('omits the finder when the section is left blank', (
    tester,
  ) async {
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

  testWidgets('re-identifying links the case to the existing animal', (
    tester,
  ) async {
    when(() => animals.searchByName('Pauli')).thenAnswer(
      (_) async => const [
        Animal(id: 'a9', species: 'Stadttaube', name: 'Pauli'),
      ],
    );
    when(
      () => cases.intake(
        any(),
        photos: any(named: 'photos'),
        idempotencyKey: any(named: 'idempotencyKey'),
      ),
    ).thenAnswer((_) async => (caseId: 'c1', animalId: 'a9'));

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

  testWidgets('pre-links the case when opened for an existing animal', (
    tester,
  ) async {
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

  testWidgets('leaving a pristine wizard pops without prompting', (
    tester,
  ) async {
    await pump(tester);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Discard changes?'), findsNothing);
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('back mid-intake asks before discarding the input', (
    tester,
  ) async {
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
    verifyNever(
      () => cases.intake(
        any(),
        photos: any(named: 'photos'),
        idempotencyKey: any(named: 'idempotencyKey'),
      ),
    );
  });

  testWidgets('progress without typing still guards against back', (
    tester,
  ) async {
    await pump(tester);

    // Advancing needs a picked reason chip — non-text input must also count
    // as unsaved progress.
    await tapNext(tester);
    await pickInjury(tester);
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Discard changes?'), findsOneWidget);
  });

  testWidgets('staged intake photos ride along on the intake call', (
    tester,
  ) async {
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

    final files =
        verify(
              () => cases.intake(
                any(),
                photos: captureAny(named: 'photos'),
                idempotencyKey: any(named: 'idempotencyKey'),
              ),
            ).captured.single
            as List<http.MultipartFile>;
    expect(files.length, 1);
    expect(files.single.field, 'intake_photos');
  });

  // ── Draft persistence (federfall-t2is) ────────────────────────────────────
  //
  // The wizard writes its in-progress values to a local store while editing so
  // an interrupted intake — an incoming call, an OS eviction, a crash — is not
  // lost. `drafts` is the in-memory stand-in for that store.

  // A draft as an interrupted wizard would have left it.
  CaseIntakeDraft storedDraft({
    int step = 0,
    String key = 'resumed-key',
    String? routeAnimalId,
    String? linkedAnimalId,
    DateTime? savedAt,
    List<String> photoPaths = const [],
    String finderFirstName = '',
    String finderPhone = '',
  }) => CaseIntakeDraft(
    savedAt: savedAt ?? DateTime.now().subtract(const Duration(minutes: 20)),
    idempotencyKey: key,
    step: step,
    routeAnimalId: routeAnimalId,
    linkedAnimalId: linkedAnimalId,
    species: 'Ringeltaube',
    name: 'Pauli',
    reasons: const ['adre1'],
    ageClass: AgeClass.adult,
    intakeWeight: '280',
    intakeNotes: 'Flügel hängt',
    finderFirstName: finderFirstName,
    finderPhone: finderPhone,
    photoPaths: photoPaths,
  );

  // Waits out the write debounce.
  Future<void> settleDraftWrite(WidgetTester tester) =>
      tester.pump(const Duration(seconds: 1));

  // Accepts the restore prompt, then waits out the confirmation snackbar so it
  // stops covering the wizard's navigation buttons.
  Future<void> continueDraft(WidgetTester tester) async {
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  testWidgets('an untouched wizard persists nothing', (tester) async {
    await pump(tester);

    // Merely paging forward is not unsaved work and must leave no draft
    // behind for the next intake to be offered.
    await tapNext(tester);
    await settleDraftWrite(tester);

    expect(drafts.writes, 0);
    expect(drafts.draft, isNull);
  });

  testWidgets('input is persisted once typing pauses', (tester) async {
    await pump(tester);

    await enterByLabel(tester, 'Name (optional)', 'Pauli');
    // Nothing is written mid-keystroke...
    await tester.pump();
    expect(drafts.writes, 0);

    // ...but the pause commits it.
    await settleDraftWrite(tester);
    expect(drafts.draft!.name, 'Pauli');
    expect(drafts.draft!.species, 'Stadttaube');
    expect(drafts.draft!.step, 0);
    expect(drafts.draft!.idempotencyKey, isNotEmpty);
  });

  testWidgets('the debounce coalesces a burst of keystrokes', (tester) async {
    await pump(tester);

    for (final value in ['P', 'Pa', 'Pau']) {
      await enterByLabel(tester, 'Name (optional)', value);
      await tester.pump(const Duration(milliseconds: 100));
    }
    await settleDraftWrite(tester);

    expect(drafts.writes, 1);
    expect(drafts.draft!.name, 'Pau');
  });

  testWidgets('non-text input is persisted too', (tester) async {
    await pump(tester);

    // Reason chips, dates and the exam switch are not Form fields, so they
    // need their own hook into the draft — a value that only lives in
    // setState is a value a crash eats.
    await tapNext(tester);
    await pickInjury(tester);
    await settleDraftWrite(tester);

    expect(drafts.draft!.reasons, ['adre1']);
    expect(drafts.draft!.step, 1);
  });

  testWidgets('backgrounding flushes the pending draft at once', (
    tester,
  ) async {
    await pump(tester);

    await enterByLabel(tester, 'Name (optional)', 'Pauli');
    await tester.pump();
    expect(drafts.writes, 0, reason: 'still inside the debounce');

    // Backgrounding is the last notice before the OS may evict the process —
    // waiting out the debounce would be too late.
    [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ].forEach(tester.binding.handleAppLifecycleStateChanged);
    await tester.pump();

    expect(drafts.writes, 1);
    expect(drafts.draft!.name, 'Pauli');
  });

  testWidgets('a stored draft is offered back and repopulates the form', (
    tester,
  ) async {
    drafts.draft = storedDraft();

    await pump(tester);

    expect(find.text('Continue unfinished intake?'), findsOneWidget);
    expect(find.text('Unfinished intake restored'), findsNothing);
    await continueDraft(tester);

    // Step 0 came back...
    expect(find.text('Pauli'), findsOneWidget);
    expect(find.text('Ringeltaube'), findsOneWidget);

    // ...and so did the steps the carer could no longer see.
    await tapNext(tester);
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, 'Injury'))
          .selected,
      isTrue,
    );
    expect(find.text('280'), findsOneWidget);
    await tapNext(tester);
    expect(find.text('Flügel hängt'), findsOneWidget);
  });

  testWidgets('a restored draft opens on the step it was left on', (
    tester,
  ) async {
    drafts.draft = storedDraft(step: 2);

    await pump(tester);
    await continueDraft(tester);

    expect(find.text('Step 3 of 3'), findsOneWidget);
  });

  testWidgets('restoring adopts the draft idempotency key', (tester) async {
    // The intake may already have committed when the app died mid-submit.
    // Resubmitting the SAME key makes the backend replay it instead of
    // admitting the bird twice — federfall-3ty3, extended across process
    // death.
    drafts.draft = storedDraft(step: 2, key: 'key-from-before-the-crash');

    await pump(tester);
    await continueDraft(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Create case'));
    await tester.pumpAndSettle();

    final key =
        verify(
              () => cases.intake(
                any(),
                photos: any(named: 'photos'),
                idempotencyKey: captureAny(named: 'idempotencyKey'),
              ),
            ).captured.single
            as String;
    expect(key, 'key-from-before-the-crash');
  });

  testWidgets('a restored draft still guards against an accidental back', (
    tester,
  ) async {
    drafts.draft = storedDraft();

    await pump(tester);
    await continueDraft(tester);
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Discard changes?'), findsOneWidget);
  });

  testWidgets('starting over throws the stored draft away', (tester) async {
    drafts.draft = storedDraft();

    await pump(tester);
    await tester.tap(find.text('Start over'));
    await tester.pumpAndSettle();

    expect(drafts.clears, 1);
    expect(drafts.draft, isNull);
    // A blank wizard, not a half-applied one.
    expect(find.text('Pauli'), findsNothing);
    expect(find.text('Stadttaube'), findsOneWidget);
  });

  testWidgets('a stale draft is purged without asking', (tester) async {
    // A day-old intake nobody finished is stale enough that restoring it risks
    // attaching yesterday's notes to today's bird.
    drafts.draft = storedDraft(
      savedAt: DateTime.now().subtract(
        CaseIntakeDraft.maxAge + const Duration(minutes: 1),
      ),
    );

    await pump(tester);

    expect(find.text('Continue unfinished intake?'), findsNothing);
    expect(drafts.clears, 1);
    expect(drafts.draft, isNull);
  });

  testWidgets('a draft from another entry point is not offered, nor deleted', (
    tester,
  ) async {
    // Started from an aviary resident; this is a blank intake, so the draft
    // belongs to a different screen and must simply be left alone.
    drafts.draft = storedDraft(routeAnimalId: 'anim9');

    await pump(tester);

    expect(find.text('Continue unfinished intake?'), findsNothing);
    expect(drafts.clears, 0);
    expect(drafts.draft, isNotNull);
  });

  testWidgets('a store that cannot be read does not block the wizard', (
    tester,
  ) async {
    drafts.readError = Exception('keystore locked');

    await pump(tester);

    expect(find.text('Continue unfinished intake?'), findsNothing);
    expect(find.text('Step 1 of 3'), findsOneWidget);
  });

  testWidgets('a committed intake clears the draft', (tester) async {
    await pump(tester);

    await enterByLabel(tester, 'Name (optional)', 'Pauli');
    await settleDraftWrite(tester);
    expect(drafts.draft, isNotNull);

    await tapNext(tester);
    await pickInjury(tester);
    await tapNext(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Create case'));
    await tester.pumpAndSettle();

    expect(find.text('CASE c1'), findsOneWidget);
    expect(drafts.draft, isNull);
  });

  testWidgets('a failed intake keeps the draft', (tester) async {
    when(
      () => cases.intake(
        any(),
        photos: any(named: 'photos'),
        idempotencyKey: any(named: 'idempotencyKey'),
      ),
    ).thenThrow(
      const RepositoryException('offline', kind: RepositoryErrorKind.network),
    );

    await pump(tester);

    await enterByLabel(tester, 'Name (optional)', 'Pauli');
    await settleDraftWrite(tester);
    await tapNext(tester);
    await pickInjury(tester);
    await tapNext(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Create case'));
    await tester.pumpAndSettle();

    // Nothing committed, so the recovery path must still be there.
    expect(drafts.draft, isNotNull);
    expect(drafts.draft!.name, 'Pauli');
  });

  testWidgets('confirming a discard removes the draft', (tester) async {
    await pump(tester);

    await enterByLabel(tester, 'Name (optional)', 'Pauli');
    await settleDraftWrite(tester);
    expect(drafts.draft, isNotNull);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    // Otherwise the next intake would be offered this thrown-away one.
    expect(find.text('HOME'), findsOneWidget);
    expect(drafts.draft, isNull);
  });

  testWidgets('staged photos are restored, and vanished ones are reported', (
    tester,
  ) async {
    // image_picker hands back files in a cache directory the OS may clear at
    // any time, so a stored path can outlive its bytes: one of these two is
    // still there, the other is gone.
    photoLoader = FakeStagedPhotoLoader(const {'/cache/kept.jpg': 'kept.jpg'});
    drafts.draft = storedDraft(
      step: 2,
      photoPaths: const ['/cache/kept.jpg', '/cache/gone.jpg'],
    );

    await pump(tester);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    // Said out loud rather than silently swallowed.
    expect(find.text('1 photo could not be restored'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    // The survivor still rides along on the intake; the dead path does not,
    // which is what keeps submit from failing on a missing file.
    await tester.tap(find.widgetWithText(FilledButton, 'Create case'));
    await tester.pumpAndSettle();
    final files =
        verify(
              () => cases.intake(
                any(),
                photos: captureAny(named: 'photos'),
                idempotencyKey: any(named: 'idempotencyKey'),
              ),
            ).captured.single
            as List<http.MultipartFile>;
    expect(files.length, 1);
  });

  testWidgets('a draft with only dead photo paths still restores', (
    tester,
  ) async {
    drafts.draft = storedDraft(step: 2, photoPaths: const ['/cache/gone.jpg']);

    await pump(tester);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('1 photo could not be restored'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    // The rest of the intake survived — only the photos were lost.
    expect(find.text('Flügel hängt'), findsOneWidget);
  });

  testWidgets('a restored draft brings its re-identified animal back', (
    tester,
  ) async {
    when(() => animals.getOne('a9')).thenAnswer(
      (_) async => const Animal(id: 'a9', species: 'Stadttaube', name: 'Pauli'),
    );
    drafts.draft = storedDraft(linkedAnimalId: 'a9');

    await pump(tester);
    await continueDraft(tester);

    expect(find.byIcon(Icons.link), findsOneWidget);

    await tapNext(tester); // linked, so step 0 needs no species
    await tapNext(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Create case'));
    await tester.pumpAndSettle();

    expect(capturedPayload()['animal'], 'a9');
  });

  testWidgets('a restored draft may deliberately hold no link at all', (
    tester,
  ) async {
    // Opened for a resident, but the carer had unlinked the animal before the
    // interruption — the draft is authoritative, so the route must not
    // silently re-link it.
    when(() => animals.getOne('a1')).thenAnswer(
      (_) async => const Animal(id: 'a1', species: 'Stadttaube', name: 'Pauli'),
    );
    drafts.draft = storedDraft(routeAnimalId: 'a1');

    await pump(tester, animalId: 'a1');
    await continueDraft(tester);

    expect(find.byIcon(Icons.link), findsNothing);
    expect(find.text('Returning bird? Search'), findsOneWidget);
  });

  testWidgets('a draft whose animal is gone still restores, without the link', (
    tester,
  ) async {
    when(() => animals.getOne('a9')).thenThrow(
      const RepositoryException('gone', kind: RepositoryErrorKind.notFound),
    );
    drafts.draft = storedDraft(linkedAnimalId: 'a9');

    await pump(tester);
    await continueDraft(tester);

    expect(find.byIcon(Icons.link), findsNothing);
    // The rest of the intake is intact — a deleted bird costs the link only.
    expect(find.text('Pauli'), findsOneWidget);
  });

  testWidgets('a reduced draft says what will not come back', (tester) async {
    // What the web store leaves behind: an XFile path there is a blob: URL
    // that dies with the document, so the photos were dropped on the way in.
    drafts.draft = storedDraft(
      photoPaths: const ['/cache/kept.jpg'],
    ).withoutPhotoPaths();
    expect(drafts.draft!.partial, isTrue, reason: 'precondition');

    await pump(tester);

    expect(
      find.textContaining('have to be added again'),
      findsOneWidget,
      reason: 'a partial draft must not restore silently',
    );
  });

  testWidgets('a full draft does not warn about anything', (tester) async {
    drafts.draft = storedDraft();

    await pump(tester);

    expect(find.textContaining('have to be added again'), findsNothing);
  });

  testWidgets("the finder's contact details come back too", (tester) async {
    // The finder section is optional but the most tedious to retype — a phone
    // number nobody wrote down is gone for good once the app is killed.
    drafts.draft = storedDraft(
      step: 2,
      finderFirstName: 'Anna',
      finderPhone: '+49 170 0000000',
    );

    await pump(tester);
    await continueDraft(tester);

    // The optional section starts collapsed, as it does for typed input.
    await tester.tap(find.text('Finder (optional)'));
    await tester.pumpAndSettle();
    expect(find.text('Anna'), findsOneWidget);
    expect(find.text('+49 170 0000000'), findsOneWidget);

    // ...and travel on to the backend on submit.
    await tester.tap(find.widgetWithText(FilledButton, 'Create case'));
    await tester.pumpAndSettle();
    final finder = capturedPayload()['finder'] as Map<String, dynamic>;
    expect(finder['first_name'], 'Anna');
    expect(finder['phone'], '+49 170 0000000');
  });

  testWidgets('typed finder details are persisted into the draft', (
    tester,
  ) async {
    await pump(tester);

    await tapNext(tester);
    await pickInjury(tester);
    await tapNext(tester);
    await tester.tap(find.text('Finder (optional)'));
    await tester.pumpAndSettle();
    await enterByLabel(tester, 'First name', 'Anna');
    await settleDraftWrite(tester);

    expect(drafts.draft!.finderFirstName, 'Anna');
  });
}
