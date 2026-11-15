import 'dart:typed_data';

import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/case_photo_gallery.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/features/cases/journal/journal_entry_sheet.dart';
import 'package:federfall/features/cases/journal/journal_entry_tile.dart';
import 'package:federfall/features/cases/journal/journal_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';

class MockJournalRepo extends Mock implements PbJournalRepository {}

class MockCasesRepo extends Mock implements PbCasesRepository {}

class MockDocumentPicker extends Mock implements DocumentPicker {}

void main() {
  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(<http.MultipartFile>[]);
  });

  late MockJournalRepo journal;
  late MockDocumentPicker documents;

  setUp(() {
    journal = MockJournalRepo();
    documents = MockDocumentPicker();
    when(
      () => journal.fileUrl(any(), any(), thumb: any(named: 'thumb')),
    ).thenReturn(Uri.parse('http://localhost/x.jpg'));
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
    final container = ProviderContainer(
      overrides: [
        currentUserProvider.overrideWith(
          (ref) async =>
              const AppUser(id: 'u1', email: 'me@x.org', org: 'org1'),
        ),
        journalRepositoryProvider.overrideWith((ref) async => journal),
        documentPickerProvider.overrideWithValue(documents),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: child),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('JournalEntryTile', () {
    testWidgets('renders the entry text', (tester) async {
      await pump(
        tester,
        const JournalEntryTile(
          entry: JournalEntry(id: 'j1', caseId: 'c1', text: 'Ate well today'),
          caseId: 'c1',
        ),
      );

      expect(find.text('Ate well today'), findsOneWidget);
    });

    testWidgets('a PDF is a named chip, never a thumbnail request', (
      tester,
    ) async {
      await pump(
        tester,
        const JournalEntryTile(
          entry: JournalEntry(
            id: 'j1',
            caseId: 'c1',
            text: 'Laborbefund',
            attachments: ['labor_0123456789.pdf', 'wunde_abcdefghij.jpg'],
          ),
          caseId: 'c1',
        ),
      );

      expect(find.widgetWithText(InputChip, 'labor.pdf'), findsOneWidget);
      verify(
        () => journal.fileUrl('j1', 'wunde_abcdefghij.jpg', thumb: '200x200'),
      ).called(greaterThan(0));
      verifyNever(
        () => journal.fileUrl(
          'j1',
          'labor_0123456789.pdf',
          thumb: any(named: 'thumb'),
        ),
      );
    });
  });

  group('JournalEntrySheet', () {
    testWidgets('saves a text entry and pops with true', (tester) async {
      when(() => journal.createWithFiles(any(), any())).thenAnswer(
        (_) async => const JournalEntry(id: 'j9', caseId: 'c1', text: 'x'),
      );

      await pump(tester, const JournalEntrySheet(caseId: 'c1'));

      await tester.enterText(find.byType(TextField), 'Looking brighter');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final body =
          verify(
                () => journal.createWithFiles(captureAny(), any()),
              ).captured.single
              as Map<String, dynamic>;
      expect(body['case'], 'c1');
      expect(body['text'], 'Looking brighter');
      expect(body['author'], 'u1');
      expect(body['org'], 'org1');
    });

    testWidgets('saves an aviary-scoped entry with no case link', (
      tester,
    ) async {
      when(() => journal.createWithFiles(any(), any())).thenAnswer(
        (_) async => const JournalEntry(id: 'j9', aviary: 'av1', text: 'x'),
      );

      await pump(tester, const JournalEntrySheet(aviaryId: 'av1'));

      await tester.enterText(find.byType(TextField), 'Cleaned the aviary');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final body =
          verify(
                () => journal.createWithFiles(captureAny(), any()),
              ).captured.single
              as Map<String, dynamic>;
      expect(body['aviary'], 'av1');
      expect(body.containsKey('case'), isFalse);
      expect(body['text'], 'Cleaned the aviary');
    });

    testWidgets('requires note text before saving', (tester) async {
      await pump(tester, const JournalEntrySheet(caseId: 'c1'));

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      verifyNever(() => journal.createWithFiles(any(), any()));
      expect(find.text('This field is required'), findsOneWidget);
    });

    testWidgets('editing updates the entry, dropping a removed attachment', (
      tester,
    ) async {
      when(() => journal.updateWithFiles(any(), any(), any())).thenAnswer(
        (_) async => const JournalEntry(id: 'j1', caseId: 'c1', text: 'x'),
      );

      const entry = JournalEntry(
        id: 'j1',
        caseId: 'c1',
        text: 'Original note',
        attachments: ['a.jpg', 'b.jpg'],
      );
      await pump(
        tester,
        const JournalEntrySheet(caseId: 'c1', entry: entry),
      );

      // The two existing attachments render with a remove badge each.
      expect(find.byIcon(Icons.cancel), findsNWidgets(2));
      await tester.tap(find.byIcon(Icons.cancel).first);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Updated note');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final captured =
          verify(
                () => journal.updateWithFiles('j1', captureAny(), any()),
              ).captured.single
              as Map<String, dynamic>;
      expect(captured['text'], 'Updated note');
      expect(captured['attachments'], ['b.jpg']);
    });

    testWidgets('a picked PDF is uploaded with the entry', (tester) async {
      when(() => journal.createWithFiles(any(), any())).thenAnswer(
        (_) async => const JournalEntry(id: 'j9', caseId: 'c1', text: 'x'),
      );
      when(() => documents.pickFiles()).thenAnswer(
        (_) async => [
          XFile.fromData(Uint8List.fromList([1]), path: 'befund.pdf'),
        ],
      );

      await pump(tester, const JournalEntrySheet(caseId: 'c1'));
      await tester.enterText(find.byType(TextField), 'Befund ist da');
      await tester.tap(find.text('Add PDF'));
      await tester.pumpAndSettle();

      // A non-image is a named chip in the form, not a photo-strip tile.
      expect(find.widgetWithText(InputChip, 'befund.pdf'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final files =
          verify(
                () => journal.createWithFiles(any(), captureAny()),
              ).captured.single
              as List<http.MultipartFile>;
      expect(files.map((f) => f.filename), ['befund.pdf']);
      expect(files.single.field, 'attachments');
    });

    testWidgets('a picked file the journal does not take is refused by name', (
      tester,
    ) async {
      when(() => documents.pickFiles()).thenAnswer(
        (_) async => [
          XFile.fromData(Uint8List.fromList([1]), path: 'arztbrief.docx'),
          XFile.fromData(Uint8List.fromList([1]), path: 'befund.pdf'),
        ],
      );

      await pump(tester, const JournalEntrySheet(caseId: 'c1'));
      await tester.tap(find.text('Add PDF'));
      await tester.pumpAndSettle();

      expect(
        find.text('File type not supported: arztbrief.docx'),
        findsOneWidget,
      );
      expect(find.widgetWithText(InputChip, 'arztbrief.docx'), findsNothing);
      expect(find.widgetWithText(InputChip, 'befund.pdf'), findsOneWidget);
    });
  });

  group('caseGallery', () {
    test('leaves a journal PDF out of the photo gallery', () async {
      final cases = MockCasesRepo();
      Uri url(String id, String f, {String? thumb}) =>
          Uri.parse('http://localhost/$id/$f${thumb == null ? '' : '?t'}');
      when(
        () => cases.fileUrl(any(), any(), thumb: any(named: 'thumb')),
      ).thenAnswer(
        (i) => url(
          i.positionalArguments[0] as String,
          i.positionalArguments[1] as String,
          thumb: i.namedArguments[#thumb] as String?,
        ),
      );
      when(
        () => journal.fileUrl(any(), any(), thumb: any(named: 'thumb')),
      ).thenAnswer(
        (i) => url(
          i.positionalArguments[0] as String,
          i.positionalArguments[1] as String,
          thumb: i.namedArguments[#thumb] as String?,
        ),
      );

      final container = ProviderContainer(
        overrides: [
          caseByIdProvider('c1').overrideWith(
            (ref) async => const Case(id: 'c1', animal: 'a1'),
          ),
          journalForCaseProvider('c1').overrideWith(
            (ref) async => const [
              JournalEntry(
                id: 'j1',
                caseId: 'c1',
                text: 'x',
                attachments: ['wunde.jpg', 'labor.pdf'],
              ),
            ],
          ),
          casesRepositoryProvider.overrideWith((ref) async => cases),
          journalRepositoryProvider.overrideWith((ref) async => journal),
        ],
      );
      addTearDown(container.dispose);

      final photos = await container.read(caseGalleryProvider('c1').future);

      expect(photos.map((p) => p.full.path), ['/j1/wunde.jpg']);
    });
  });

  group('journal entry actions', () {
    testWidgets('deletes an entry after confirmation', (tester) async {
      when(() => journal.delete('j1')).thenAnswer((_) async {});

      await pump(
        tester,
        const JournalEntryTile(
          entry: JournalEntry(id: 'j1', caseId: 'c1', text: 'Ate well today'),
          caseId: 'c1',
        ),
      );

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();

      // Confirm in the dialog.
      await tester.tap(find.widgetWithText(DestructiveActionButton, 'Delete'));
      await tester.pumpAndSettle();

      verify(() => journal.delete('j1')).called(1);
    });
  });
}
