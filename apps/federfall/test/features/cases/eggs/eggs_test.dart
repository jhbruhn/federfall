import 'dart:typed_data';

import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/eggs/egg_entry_sheet.dart';
import 'package:federfall/features/cases/eggs/egg_entry_tile.dart';
import 'package:federfall/features/cases/eggs/eggs_providers.dart';
import 'package:federfall/features/cases/journal/journal_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart' hide Finder;
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:mocktail/mocktail.dart';

class MockEggRepo extends Mock implements PbEggRecordsRepository {}

class MockPicker extends Mock implements ImagePicker {}

EggRecord _egg(
  String id, {
  DateTime? laidAt,
  int count = 1,
  String animal = 'anml1',
  EggAttribution attribution = EggAttribution.confirmed,
  String? author,
  List<String> photos = const [],
}) => EggRecord(
  id: id,
  animal: animal,
  count: count,
  laidAt: laidAt,
  attribution: attribution,
  author: author,
  photos: photos,
);

void main() {
  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(<http.MultipartFile>[]);
  });

  group('groupIntoClutches', () {
    test('keeps eggs within the gap in one clutch and splits beyond it', () {
      // Two eggs ~44 h apart (one clutch), then the next clutch weeks later.
      final clutches = groupIntoClutches([
        _egg('e1', laidAt: DateTime.utc(2026, 6)),
        _egg('e2', laidAt: DateTime.utc(2026, 6, 3)),
        _egg('e3', laidAt: DateTime.utc(2026, 6, 24)),
      ]);
      expect(clutches.map((c) => c.map((e) => e.id).toList()), [
        ['e1', 'e2'],
        ['e3'],
      ]);
    });

    test('exactly the gap still counts as the same clutch', () {
      final clutches = groupIntoClutches([
        _egg('e1', laidAt: DateTime.utc(2026, 6)),
        _egg('e2', laidAt: DateTime.utc(2026, 6, 1 + kClutchGapDays)),
      ]);
      expect(clutches, hasLength(1));
    });

    test('one hour past the gap starts a new clutch', () {
      final clutches = groupIntoClutches([
        _egg('e1', laidAt: DateTime.utc(2026, 6)),
        _egg('e2', laidAt: DateTime.utc(2026, 6, 1 + kClutchGapDays, 1)),
      ]);
      expect(clutches, hasLength(2));
    });

    test('sorts before grouping, so input order does not matter', () {
      final clutches = groupIntoClutches([
        _egg('e3', laidAt: DateTime.utc(2026, 6, 24)),
        _egg('e1', laidAt: DateTime.utc(2026, 6)),
        _egg('e2', laidAt: DateTime.utc(2026, 6, 3)),
      ]);
      expect(clutches.map((c) => c.length), [2, 1]);
      expect(clutches.first.first.id, 'e1');
    });

    test('an empty ledger has no clutches', () {
      expect(groupIntoClutches(const []), isEmpty);
    });
  });

  group('clutchContaining', () {
    test('returns the whole clutch the record belongs to', () {
      final eggs = [
        _egg('e1', laidAt: DateTime.utc(2026, 6)),
        _egg('e2', laidAt: DateTime.utc(2026, 6, 3)),
        _egg('e3', laidAt: DateTime.utc(2026, 6, 24)),
      ];
      expect(clutchContaining(eggs, eggs[1]).map((e) => e.id), ['e1', 'e2']);
      expect(clutchContaining(eggs, eggs[2]).map((e) => e.id), ['e3']);
    });
  });

  group('eggsInCaseWindow', () {
    CaseBundle bundleFor({DateTime? admitted, DateTime? disposed}) =>
        CaseBundle(
          medicalCase: Case(id: 'c1', animal: 'anml1', admittedAt: admitted),
          dispositions: [
            if (disposed != null)
              Disposition(id: 'd1', caseId: 'c1', disposedAt: disposed),
          ],
        );

    test('drops eggs laid before admission', () {
      final kept = eggsInCaseWindow([
        _egg('before', laidAt: DateTime.utc(2026, 5)),
        _egg('during', laidAt: DateTime.utc(2026, 6, 5)),
      ], bundleFor(admitted: DateTime.utc(2026, 6)));
      expect(kept.map((e) => e.id), ['during']);
    });

    test('drops eggs laid after the case was closed out', () {
      final kept = eggsInCaseWindow(
        [
          _egg('during', laidAt: DateTime.utc(2026, 6, 5)),
          _egg('after', laidAt: DateTime.utc(2026, 8)),
        ],
        bundleFor(
          admitted: DateTime.utc(2026, 6),
          disposed: DateTime.utc(2026, 7),
        ),
      );
      expect(kept.map((e) => e.id), ['during']);
    });

    test('an open case runs up to now', () {
      final kept = eggsInCaseWindow([
        _egg(
          'recent',
          laidAt: DateTime.now().subtract(const Duration(days: 1)),
        ),
        _egg('future', laidAt: DateTime.now().add(const Duration(days: 5))),
      ], bundleFor(admitted: DateTime.utc(2026)));
      expect(kept.map((e) => e.id), ['recent']);
    });

    test('a case with no admission date is unbounded at the start', () {
      final kept = eggsInCaseWindow([
        _egg('old', laidAt: DateTime.utc(2020)),
      ], bundleFor());
      expect(kept.map((e) => e.id), ['old']);
    });

    test('an undated record cannot be placed and is dropped', () {
      expect(
        eggsInCaseWindow([_egg('undated')], bundleFor()),
        isEmpty,
      );
    });
  });

  group('EggLayingSummary', () {
    test('sums count rather than counting rows, and splits out presumed', () {
      final now = DateTime.utc(2026, 7);
      final summary = EggLayingSummary.from([
        _egg('e1', laidAt: DateTime.utc(2026, 6), count: 2),
        _egg(
          'e2',
          laidAt: DateTime.utc(2026, 6, 20),
          attribution: EggAttribution.presumed,
        ),
        // Outside the rolling 12-month window.
        _egg('e3', laidAt: DateTime.utc(2024), count: 3),
      ], now: now);

      expect(summary.totalEggs, 6);
      expect(summary.eggsLast12Months, 3);
      expect(summary.presumedEggs, 1);
      expect(summary.lastLaidAt, DateTime.utc(2026, 6, 20));
      expect(summary.isEmpty, isFalse);
    });

    test('an empty ledger is empty', () {
      expect(EggLayingSummary.from(const []).isEmpty, isTrue);
    });
  });

  group('widgets', () {
    late MockEggRepo eggs;
    late MockPicker picker;

    setUp(() {
      eggs = MockEggRepo();
      picker = MockPicker();
      when(
        () => eggs.fileUrl(any(), any(), thumb: any(named: 'thumb')),
      ).thenReturn(Uri.parse('http://localhost/egg.jpg'));
    });

    Future<void> pump(
      WidgetTester tester,
      Widget child, {
      AppUser me = const AppUser(id: 'u1', email: 'me@x.org', org: 'org1'),
    }) async {
      final container = ProviderContainer(
        overrides: [
          currentUserProvider.overrideWith((ref) async => me),
          eggRecordsRepositoryProvider.overrideWith((ref) async => eggs),
          imagePickerProvider.overrideWithValue(picker),
        ],
      );
      addTearDown(container.dispose);

      // The sheet is taller than the default 800px test viewport, which would
      // leave the save button (and the photo strip) off-screen and un-tappable.
      tester.view.physicalSize = const Size(1000, 2400);
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

    testWidgets('the sheet logs a laying event on the animal, never a case', (
      tester,
    ) async {
      when(
        () => eggs.createWithFiles(any(), any()),
      ).thenAnswer((_) async => _egg('e9'));

      await pump(tester, const EggEntrySheet(animalId: 'anml1'));
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final body =
          verify(
                () => eggs.createWithFiles(captureAny(), any()),
              ).captured.single
              as Map<String, dynamic>;
      expect(body['animal'], 'anml1');
      expect(body['count'], 1);
      expect(body['attribution'], 'confirmed');
      expect(body['author'], 'u1');
      expect(body['org'], 'org1');
      // The whole point of the design: no case relation exists to send.
      expect(body.containsKey('case'), isFalse);
    });

    testWidgets('the count stepper raises the number of eggs', (tester) async {
      when(
        () => eggs.createWithFiles(any(), any()),
      ).thenAnswer((_) async => _egg('e9'));

      await pump(tester, const EggEntrySheet(animalId: 'anml1'));
      expect(find.text('1 egg'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.pumpAndSettle();
      expect(find.text('2 eggs'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final body =
          verify(
                () => eggs.createWithFiles(captureAny(), any()),
              ).captured.single
              as Map<String, dynamic>;
      expect(body['count'], 2);
    });

    testWidgets('the count never drops below one egg', (tester) async {
      await pump(tester, const EggEntrySheet(animalId: 'anml1'));
      final minus = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.remove_circle_outline),
          matching: find.byType(IconButton),
        ),
      );
      expect(minus.onPressed, isNull);
    });

    testWidgets('"layer uncertain" records the egg as presumed', (
      tester,
    ) async {
      when(
        () => eggs.createWithFiles(any(), any()),
      ).thenAnswer((_) async => _egg('e9'));

      await pump(tester, const EggEntrySheet(animalId: 'anml1'));
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final body =
          verify(
                () => eggs.createWithFiles(captureAny(), any()),
              ).captured.single
              as Map<String, dynamic>;
      expect(body['attribution'], 'presumed');
    });

    testWidgets('picked photos upload as multipart files on the photos field', (
      tester,
    ) async {
      when(picker.pickMultiImage).thenAnswer(
        (_) async => [
          XFile.fromData(
            Uint8List.fromList([1, 2, 3]),
            name: 'windei.jpg',
            mimeType: 'image/jpeg',
          ),
          XFile.fromData(
            Uint8List.fromList([4, 5, 6]),
            name: 'windei2.jpg',
            mimeType: 'image/jpeg',
          ),
        ],
      );
      when(
        () => eggs.createWithFiles(any(), any()),
      ).thenAnswer((_) async => _egg('e9'));

      await pump(tester, const EggEntrySheet(animalId: 'anml1'));
      await tester.tap(find.widgetWithText(OutlinedButton, 'Add photos'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final files =
          verify(
                () => eggs.createWithFiles(any(), captureAny()),
              ).captured.single
              as List<http.MultipartFile>;
      expect(files, hasLength(2));
      expect(files.every((f) => f.field == 'photos'), isTrue);
    });

    testWidgets('editing sends the surviving photos and no animal/org', (
      tester,
    ) async {
      when(
        () => eggs.updateWithFiles(any(), any(), any()),
      ).thenAnswer((_) async => _egg('e1'));

      await pump(
        tester,
        EggEntrySheet(
          animalId: 'anml1',
          egg: _egg('e1', count: 2, photos: const ['a.jpg', 'b.jpg']),
        ),
      );

      expect(find.byIcon(Icons.cancel), findsNWidgets(2));
      await tester.tap(find.byIcon(Icons.cancel).first);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final body =
          verify(
                () => eggs.updateWithFiles('e1', captureAny(), any()),
              ).captured.single
              as Map<String, dynamic>;
      expect(body['photos'], ['b.jpg']);
      expect(body['count'], 2);
      expect(body.containsKey('animal'), isFalse);
      expect(body.containsKey('org'), isFalse);
    });

    testWidgets('the tile shows the count, outcome and the presumed badge', (
      tester,
    ) async {
      await pump(
        tester,
        EggEntryTile(
          egg: EggRecord(
            id: 'e1',
            animal: 'anml1',
            count: 2,
            laidAt: DateTime.utc(2026, 6, 2),
            fertility: EggFertility.infertile,
            fate: EggFate.dummySwapped,
            attribution: EggAttribution.presumed,
            notes: 'Thin shell',
          ),
          caseId: 'c1',
        ),
      );

      expect(
        find.text('2 eggs · Infertile · Swapped for a dummy'),
        findsOneWidget,
      );
      expect(find.text('presumed'), findsOneWidget);
      expect(find.text('Thin shell'), findsOneWidget);
    });

    testWidgets('an unknown fertility/outcome is left off the tile', (
      tester,
    ) async {
      await pump(
        tester,
        EggEntryTile(egg: _egg('e1', laidAt: DateTime.utc(2026, 6, 2))),
      );

      expect(find.text('1 egg'), findsOneWidget);
    });

    testWidgets('only the author or a supervisor may delete', (tester) async {
      await pump(
        tester,
        EggEntryTile(egg: _egg('e1', author: 'someone-else')),
      );
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      expect(find.text('Delete'), findsNothing);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      await pump(
        tester,
        EggEntryTile(egg: _egg('e1', author: 'u1')),
      );
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets("a supervisor may delete another carer's record", (
      tester,
    ) async {
      when(() => eggs.delete('e1')).thenAnswer((_) async {});

      await pump(
        tester,
        EggEntryTile(egg: _egg('e1', author: 'someone-else')),
        me: const AppUser(
          id: 'sup',
          email: 'sup@x.org',
          org: 'org1',
          role: UserRole.supervisor,
        ),
      );

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();

      verify(() => eggs.delete('e1')).called(1);
    });
  });
}
