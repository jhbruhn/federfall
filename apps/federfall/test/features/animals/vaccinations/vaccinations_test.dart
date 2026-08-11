import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/auth/roles.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/animals/custody_providers.dart';
import 'package:federfall/features/animals/vaccinations/vaccination_sheet.dart';
import 'package:federfall/features/animals/vaccinations/vaccination_tile.dart';
import 'package:federfall/features/animals/vaccinations/vaccinations_providers.dart';
import 'package:federfall/features/cases/journal/journal_providers.dart';
import 'package:federfall/features/cases/markings/marking_types_providers.dart';
import 'package:federfall/features/cases/medications/medication_routes_providers.dart';
import 'package:federfall/l10n/l10n.dart';
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
    }) async {
      final container = ProviderContainer(
        overrides: [
          currentUserProvider.overrideWith((ref) async => me),
          vaccinationsRepositoryProvider.overrideWith((ref) async => repo),
          vaccineLabelsRepositoryProvider.overrideWith((ref) async => labels),
          imagePickerProvider.overrideWithValue(picker),
          medicationRoutesProvider.overrideWith((ref) async => const []),
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
}
