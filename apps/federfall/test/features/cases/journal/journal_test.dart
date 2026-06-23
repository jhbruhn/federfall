import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/journal/journal_entry_sheet.dart';
import 'package:federfall/features/cases/journal/journal_entry_tile.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';

class MockJournalRepo extends Mock implements PbJournalRepository {}

void main() {
  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(<http.MultipartFile>[]);
  });

  late MockJournalRepo journal;

  setUp(() {
    journal = MockJournalRepo();
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
      ],
    );
    addTearDown(container.dispose);

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

      final body = verify(
        () => journal.createWithFiles(captureAny(), any()),
      ).captured.single as Map<String, dynamic>;
      expect(body['case'], 'c1');
      expect(body['text'], 'Looking brighter');
      expect(body['author'], 'u1');
      expect(body['org'], 'org1');
    });

    testWidgets('requires note text before saving', (tester) async {
      await pump(tester, const JournalEntrySheet(caseId: 'c1'));

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      verifyNever(() => journal.createWithFiles(any(), any()));
      expect(find.text('This field is required'), findsOneWidget);
    });

    testWidgets('editing updates the entry, dropping a removed attachment',
        (tester) async {
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

      final captured = verify(
        () => journal.updateWithFiles('j1', captureAny(), any()),
      ).captured.single as Map<String, dynamic>;
      expect(captured['text'], 'Updated note');
      expect(captured['attachments'], ['b.jpg']);
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
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();

      verify(() => journal.delete('j1')).called(1);
    });
  });
}
