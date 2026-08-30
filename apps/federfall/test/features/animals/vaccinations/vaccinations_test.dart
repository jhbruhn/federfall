import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/auth/roles.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/animals/custody_providers.dart';
import 'package:federfall/features/animals/vaccinations/batch_vaccination_sheet.dart';
import 'package:federfall/features/animals/vaccinations/vaccination_sheet.dart';
import 'package:federfall/features/animals/vaccinations/vaccination_tile.dart';
import 'package:federfall/features/animals/vaccinations/vaccinations_providers.dart';
import 'package:federfall/features/aviaries/aviaries_providers.dart';
import 'package:federfall/features/cases/journal/journal_providers.dart';
import 'package:federfall/features/cases/markings/marking_types_providers.dart';
import 'package:federfall/features/cases/medications/medication_routes_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart' hide Finder;
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:mocktail/mocktail.dart';

class MockVaccinationsRepo extends Mock implements PbVaccinationsRepository {}

class MockVaccineLabelsRepo extends Mock implements PbVaccineLabelsRepository {}

class MockPicker extends Mock implements ImagePicker {}

Vaccination _shot(
  String id, {
  DateTime? at,
  String vaccine = 'Colombovac PMV',
  String? target = 'Paramyxovirose',
  DateTime? nextDueAt,
  String? author,
}) => Vaccination(
  id: id,
  animal: 'anml1',
  vaccine: vaccine,
  target: target,
  administeredAt: at,
  nextDueAt: nextDueAt,
  author: author,
  created: at ?? DateTime.utc(2026),
);

void main() {
  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(<http.MultipartFile>[]);
  });

  group('the per-target roll-up', () {
    test('answers "what is this bird protected against", newest first', () {
      final statuses = vaccinationStatuses([
        _shot('v1', at: DateTime.utc(2025, 3)),
        _shot('v2', at: DateTime.utc(2026, 3)),
        _shot('v3', at: DateTime.utc(2026, 6), target: 'Pocken'),
      ]);

      expect(statuses.map((s) => s.target), ['Pocken', 'Paramyxovirose']);
      // The LATEST shot represents the target, not the first one recorded.
      expect(statuses.last.last.id, 'v2');
      expect(statuses.last.count, 2);
    });

    test('groups case-insensitively but shows what was recorded', () {
      final statuses = vaccinationStatuses([
        _shot('v1', at: DateTime.utc(2026, 1, 15), target: 'paramyxovirose'),
        _shot('v2', at: DateTime.utc(2026, 5), target: '  Paramyxovirose '),
      ]);

      expect(statuses, hasLength(1));
      expect(statuses.single.count, 2);
      // Trimmed, but never re-cased: the label is the latest record's own.
      expect(statuses.single.target, 'Paramyxovirose');
    });

    test('shots recorded without a target group together, not away', () {
      final statuses = vaccinationStatuses([
        _shot('v1', at: DateTime.utc(2026, 1, 15), target: null),
        _shot('v2', at: DateTime.utc(2026, 2), target: ''),
      ]);

      expect(statuses, hasLength(1));
      expect(statuses.single.target, isNull);
      expect(statuses.single.count, 2);
    });

    test('a booster is due once its date has passed, never before', () {
      final now = DateTime.utc(2026, 8, 11);
      final due = vaccinationStatuses([
        _shot(
          'v1',
          at: DateTime.utc(2025, 8),
          nextDueAt: DateTime.utc(2026, 8),
        ),
      ]).single;
      final planned = vaccinationStatuses([
        _shot(
          'v2',
          at: DateTime.utc(2026, 8),
          nextDueAt: DateTime.utc(2027, 8),
        ),
      ]).single;

      expect(due.isDue(now: now), isTrue);
      expect(planned.isDue(now: now), isFalse);
    });

    test('no planned booster is not the same as overdue', () {
      final status = vaccinationStatuses([
        _shot('v1', at: DateTime.utc(2020)),
      ]).single;

      expect(status.nextDueAt, isNull);
      expect(status.isDue(now: DateTime.utc(2026, 8, 11)), isFalse);
    });
  });

  group('the case window', () {
    CaseBundle bundleFor({DateTime? admittedAt, DateTime? disposedAt}) =>
        CaseBundle(
          medicalCase: Case(
            id: 'c1',
            animal: 'anml1',
            caseNumber: '2026-001',
            admittedAt: admittedAt,
          ),
          dispositions: [
            if (disposedAt != null)
              Disposition(
                id: 'd1',
                caseId: 'c1',
                type: DispositionType.released,
                disposedAt: disposedAt,
              ),
          ],
        );

    test('drops shots given before this case admitted the bird', () {
      final kept = vaccinationsInCaseWindow(
        [
          _shot('old', at: DateTime.utc(2024, 5)),
          _shot('mine', at: DateTime.utc(2026, 5)),
        ],
        bundleFor(admittedAt: DateTime.utc(2026, 4)),
      );

      expect(kept.map((v) => v.id), ['mine']);
    });

    test('and shots given after it ended — a later stay is not this one', () {
      final kept = vaccinationsInCaseWindow(
        [
          _shot('during', at: DateTime.utc(2026, 5)),
          _shot('after', at: DateTime.utc(2026, 9)),
        ],
        bundleFor(
          admittedAt: DateTime.utc(2026, 4),
          disposedAt: DateTime.utc(2026, 6),
        ),
      );

      expect(kept.map((v) => v.id), ['during']);
    });
  });

  group('deleting', () {
    const author = AppUser(id: 'u1', email: 'me@x.org', org: 'org1');
    const other = AppUser(id: 'u2', email: 'you@x.org', org: 'org1');
    const sup = AppUser(
      id: 'u3',
      email: 'sup@x.org',
      org: 'org1',
      role: UserRole.supervisor,
    );

    test('is the author or a supervisor, mirroring the server rule', () {
      final shot = _shot('v1', author: 'u1');

      expect(vaccinationDeletableBy(shot, author), isTrue);
      expect(vaccinationDeletableBy(shot, sup), isTrue);
      expect(vaccinationDeletableBy(shot, other), isFalse);
      expect(vaccinationDeletableBy(shot, null), isFalse);
    });
  });

  group('widgets', () {
    late MockVaccinationsRepo repo;
    late MockVaccineLabelsRepo labels;
    late MockPicker picker;

    setUp(() {
      repo = MockVaccinationsRepo();
      labels = MockVaccineLabelsRepo();
      picker = MockPicker();
      when(() => labels.all()).thenAnswer((_) async => const []);
      when(
        () => repo.fileUrl(any(), any(), thumb: any(named: 'thumb')),
      ).thenReturn(Uri.parse('http://localhost/vial.jpg'));
    });

    // A vaccination follows CUSTODY of the bird (1700000087), so the fixture
    // has to grant it: without this the tile's menu never renders and the
    // author-rule assertions would pass for the wrong reason.
    Future<void> pump(
      WidgetTester tester,
      Widget child, {
      AppUser me = const AppUser(id: 'u1', email: 'me@x.org', org: 'org1'),
      bool holdsBird = true,
      List<MedicationRoute> routes = const [],
    }) async {
      final container = ProviderContainer(
        overrides: [
          currentUserProvider.overrideWith((ref) async => me),
          vaccinationsRepositoryProvider.overrideWith((ref) async => repo),
          vaccineLabelsRepositoryProvider.overrideWith((ref) async => labels),
          imagePickerProvider.overrideWithValue(picker),
          medicationRoutesProvider.overrideWith((ref) async => routes),
          markingTypesProvider.overrideWith((ref) async => const []),
          canWriteAnimalProvider(
            'anml1',
          ).overrideWith((ref) async => holdsBird),
        ],
      );
      addTearDown(container.dispose);

      // The sheet is taller than the default 800px test viewport, which would
      // leave the save button off-screen and un-tappable.
      tester.view.physicalSize = const Size(1000, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: child),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the sheet records a shot on the animal, never a case', (
      tester,
    ) async {
      when(
        () => repo.createWithFiles(any(), any()),
      ).thenAnswer((_) async => _shot('v9'));

      await pump(tester, const VaccinationSheet(animalId: 'anml1'));
      await tester.enterText(
        find.byType(TextField).first,
        'Colombovac PMV',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final body =
          verify(
                () => repo.createWithFiles(captureAny(), any()),
              ).captured.single
              as Map<String, dynamic>;
      expect(body['animal'], 'anml1');
      expect(body['vaccine'], 'Colombovac PMV');
      expect(body['author'], 'u1');
      expect(body['org'], 'org1');
      // The whole point of the design: no case relation exists to send.
      expect(body.containsKey('case'), isFalse);
    });

    testWidgets('the product is required — an empty one saves nothing', (
      tester,
    ) async {
      await pump(tester, const VaccinationSheet(animalId: 'anml1'));
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      verifyNever(() => repo.createWithFiles(any(), any()));
      expect(find.text('This field is required'), findsOneWidget);
    });

    testWidgets('an overdue booster is badged on the tile', (tester) async {
      await pump(
        tester,
        VaccinationTile(
          vaccination: _shot(
            'v1',
            at: DateTime.utc(2025, 8),
            nextDueAt: DateTime.utc(2025, 9),
          ),
        ),
      );

      expect(find.text('due'), findsOneWidget);
    });

    testWidgets('a planned one in the future is not', (tester) async {
      await pump(
        tester,
        VaccinationTile(
          vaccination: _shot(
            'v1',
            at: DateTime.now(),
            nextDueAt: DateTime.now().add(const Duration(days: 300)),
          ),
        ),
      );

      expect(find.text('due'), findsNothing);
    });

    // Everything the tile can say about one shot, in the one order it says it.
    // Each of these is a separate conditional line, and an absent one is not a
    // rendering detail: a batch number that stops printing takes the only
    // evidence a vaccination happened with it.
    testWidgets('a fully recorded shot prints every line it has', (
      tester,
    ) async {
      await pump(
        tester,
        VaccinationTile(
          vaccination: Vaccination(
            id: 'v1',
            animal: 'anml1',
            vaccine: 'Colombovac PMV',
            target: 'Paramyxovirose',
            administeredAt: DateTime.utc(2026, 5, 4),
            batch: 'L-2261',
            dose: 0.25,
            series: VaccinationSeries.primary,
            vet: 'Praxis Dr. Vogel',
            notes: 'Left breast muscle',
            nextDueAt: DateTime.utc(2027, 5, 4),
          ),
        ),
      );

      expect(find.text('Colombovac PMV'), findsOneWidget);
      expect(find.text('Paramyxovirose'), findsOneWidget);
      // Dose and series share one line, joined by a middot; the route is empty
      // here because the fixture's route list is.
      expect(find.text('0.25 ml · Primary course'), findsOneWidget);
      expect(find.text('Batch L-2261'), findsOneWidget);
      expect(find.text('Praxis Dr. Vogel'), findsOneWidget);
      expect(find.text('Left breast muscle'), findsOneWidget);
      expect(find.textContaining('Booster due'), findsOneWidget);
      // Still a year out, so the due line is not the error-coloured one.
      expect(find.text('due'), findsNothing);
    });

    testWidgets('a shot recorded with nothing but a product says only that', (
      tester,
    ) async {
      await pump(
        tester,
        const VaccinationTile(
          vaccination: Vaccination(
            id: 'v1',
            animal: 'anml1',
            vaccine: 'Colombovac PMV',
            target: '',
          ),
        ),
      );

      expect(find.text('Colombovac PMV'), findsOneWidget);
      // No empty target line, no bare middot where a detail would have been.
      expect(find.textContaining('·'), findsNothing);
      expect(find.textContaining('Batch'), findsNothing);
    });

    testWidgets('the route is named, once the vocabulary has loaded', (
      tester,
    ) async {
      await pump(
        tester,
        const VaccinationTile(
          vaccination: Vaccination(
            id: 'v1',
            animal: 'anml1',
            vaccine: 'Colombovac PMV',
            route: 'r1',
            dose: 0.5,
          ),
        ),
        routes: const [
          MedicationRoute(id: 'r1', label: 'subcutaneous'),
        ],
      );

      expect(find.text('0.5 ml · subcutaneous'), findsOneWidget);
    });

    testWidgets('attachments become a thumbnail strip', (tester) async {
      await pump(
        tester,
        const VaccinationTile(
          vaccination: Vaccination(
            id: 'v1',
            animal: 'anml1',
            vaccine: 'Colombovac PMV',
            attachments: ['vial.jpg', 'ausweis.jpg'],
          ),
        ),
      );

      expect(find.byType(VaccinationImageStrip), findsOneWidget);
      // The URLs stay token-free — the access token is appended at download
      // time by the cache manager.
      verify(
        () => repo.fileUrl('v1', 'vial.jpg', thumb: '200x200'),
      ).called(greaterThan(0));
    });

    testWidgets('the author can delete, and the record goes with it', (
      tester,
    ) async {
      when(() => repo.delete(any())).thenAnswer((_) async {});

      await pump(
        tester,
        VaccinationTile(vaccination: _shot('v1', author: 'u1')),
      );

      await tester.tap(find.byType(PopupMenuButton<void>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete vaccination').last);
      await tester.pumpAndSettle();

      // The confirmation names what is lost, because nothing can evidence the
      // batch number afterwards.
      expect(find.textContaining('removed permanently'), findsOneWidget);
      await tester.tap(
        find.widgetWithText(DestructiveActionButton, 'Delete vaccination'),
      );
      await tester.pumpAndSettle();

      verify(() => repo.delete('v1')).called(1);
    });

    testWidgets("somebody else's shot offers edit but not delete", (
      tester,
    ) async {
      await pump(
        tester,
        VaccinationTile(vaccination: _shot('v1', author: 'u2')),
      );

      await tester.tap(find.byType(PopupMenuButton<void>));
      await tester.pumpAndSettle();

      // Custody lets anyone holding the bird correct a record; deleting one is
      // the author's or a supervisor's, mirroring 1700000087. The item is
      // absent rather than greyed out — the menu builds no entry without an
      // action behind it.
      expect(find.text('Edit vaccination'), findsOneWidget);
      expect(find.text('Delete vaccination'), findsNothing);
    });

    testWidgets('a member who does not hold the bird gets no menu', (
      tester,
    ) async {
      await pump(
        tester,
        VaccinationTile(vaccination: _shot('v1', author: 'u1')),
        holdsBird: false,
      );

      expect(find.byType(PopupMenuButton<void>), findsNothing);
    });
  });

  group('the batch sheet', () {
    late MockVaccinationsRepo repo;
    late MockVaccineLabelsRepo labels;

    // Three residents of one enclosure. `blocked` is the case a real roster
    // produces and the route refuses over: a bird in the aviary whose open case
    // belongs to somebody else.
    const residents = [
      Animal(id: 'a1', species: 'Stadttaube', name: 'Erna'),
      Animal(id: 'a2', species: 'Stadttaube', name: 'Fritz'),
      Animal(id: 'a3', species: 'Stadttaube', name: 'Fremd'),
    ];

    setUp(() {
      repo = MockVaccinationsRepo();
      labels = MockVaccineLabelsRepo();
      when(() => labels.all()).thenAnswer((_) async => const []);
      when(
        () => repo.vaccinateBatch(
          any(),
          any(),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      ).thenAnswer((_) async => 2);
    });

    Future<void> pumpBatch(
      WidgetTester tester, {
      Set<String> holds = const {'a1', 'a2'},
    }) async {
      final container = ProviderContainer(
        overrides: [
          currentUserProvider.overrideWith(
            (ref) async =>
                const AppUser(id: 'u1', email: 'me@x.org', org: 'org1'),
          ),
          vaccinationsRepositoryProvider.overrideWith((ref) async => repo),
          vaccineLabelsRepositoryProvider.overrideWith((ref) async => labels),
          medicationRoutesProvider.overrideWith((ref) async => const []),
          aviaryResidentsProvider('av1').overrideWith((ref) async => residents),
          for (final a in residents)
            canWriteAnimalProvider(
              a.id,
            ).overrideWith((ref) async => holds.contains(a.id)),
        ],
      );
      addTearDown(container.dispose);

      tester.view.physicalSize = const Size(1000, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            locale: Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: BatchVaccinationSheet(aviaryId: 'av1')),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('preselects every bird the keeper holds, and sends them all', (
      tester,
    ) async {
      await pumpBatch(tester);
      await tester.enterText(find.byType(TextField).first, 'Colombovac PMV');
      await tester.tap(find.text('Vaccinate 2 birds'));
      await tester.pumpAndSettle();

      final call = verify(
        () => repo.vaccinateBatch(
          captureAny(),
          captureAny(),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      ).captured;
      expect(call[0], ['a1', 'a2']);
      expect((call[1] as Map<String, dynamic>)['vaccine'], 'Colombovac PMV');
      // One shared record — the animal is the route's to set, per bird.
      expect((call[1] as Map<String, dynamic>).containsKey('animal'), isFalse);
    });

    testWidgets(
      "a bird in someone else's care is shown, disabled and skipped",
      (
        tester,
      ) async {
        await pumpBatch(tester);

        // Shown, so "this one was not vaccinated" is a fact the keeper leaves
        // with rather than a silent omission.
        expect(find.text('Fremd'), findsOneWidget);
        expect(
          find.text("In someone else's care — not vaccinated"),
          findsOneWidget,
        );
        expect(
          find.text("1 bird is in someone else's care and will be skipped"),
          findsOneWidget,
        );
        // ...and not counted in what the button promises.
        expect(find.text('Vaccinate 2 birds'), findsOneWidget);
      },
    );

    testWidgets('unticking a bird leaves it out of the batch', (tester) async {
      await pumpBatch(tester);
      await tester.enterText(find.byType(TextField).first, 'Colombovac PMV');
      await tester.tap(find.text('Fritz'));
      await tester.pumpAndSettle();

      expect(find.text('Vaccinate 1 bird'), findsOneWidget);
      await tester.tap(find.text('Vaccinate 1 bird'));
      await tester.pumpAndSettle();

      final call = verify(
        () => repo.vaccinateBatch(
          captureAny(),
          any(),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      ).captured;
      expect(call.single, ['a1']);
    });

    testWidgets('with nothing selected it writes nothing', (tester) async {
      await pumpBatch(tester, holds: const {});
      await tester.tap(find.text('None selected'));
      await tester.pumpAndSettle();

      verifyNever(
        () => repo.vaccinateBatch(
          any(),
          any(),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      );
    });

    testWidgets('the product is required here too', (tester) async {
      await pumpBatch(tester);
      await tester.tap(find.text('Vaccinate 2 birds'));
      await tester.pumpAndSettle();

      verifyNever(
        () => repo.vaccinateBatch(
          any(),
          any(),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      );
      expect(find.text('This field is required'), findsOneWidget);
    });

    testWidgets('one idempotency key survives a retry', (tester) async {
      var attempt = 0;
      final keys = <String?>[];
      when(
        () => repo.vaccinateBatch(
          any(),
          any(),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      ).thenAnswer((inv) async {
        keys.add(inv.namedArguments[#idempotencyKey] as String?);
        if (attempt++ == 0) throw Exception('network');
        return 2;
      });

      await pumpBatch(tester);
      await tester.enterText(find.byType(TextField).first, 'Colombovac PMV');
      await tester.tap(find.text('Vaccinate 2 birds'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vaccinate 2 birds'));
      await tester.pumpAndSettle();

      // The same key both times: the server replays the committed batch rather
      // than vaccinating the flock a second time.
      expect(keys, hasLength(2));
      expect(keys.first, isNotNull);
      expect(keys.first, keys.last);
    });
  });
}
