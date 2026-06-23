import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/journal/journal_section.dart';
import 'package:federfall/features/cases/journal/new_journal_entry_sheet.dart';
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

  group('JournalSection', () {
    testWidgets('shows the empty state when there are no entries',
        (tester) async {
      when(() => journal.forCase('c1')).thenAnswer((_) async => []);

      await pump(tester, const JournalSection(caseId: 'c1'));

      expect(find.text('No journal entries yet'), findsOneWidget);
    });

    testWidgets('renders entries newest-first with their date and text',
        (tester) async {
      when(() => journal.forCase('c1')).thenAnswer(
        (_) async => [
          JournalEntry(
            id: 'j1',
            caseId: 'c1',
            text: 'Ate well today',
            entryAt: DateTime.utc(2026, 6, 22),
          ),
        ],
      );

      await pump(tester, const JournalSection(caseId: 'c1'));

      expect(find.text('Ate well today'), findsOneWidget);
    });
  });

  group('NewJournalEntrySheet', () {
    testWidgets('saves a text entry and pops with true', (tester) async {
      when(() => journal.createWithFiles(any(), any())).thenAnswer(
        (_) async => const JournalEntry(id: 'j9', caseId: 'c1', text: 'x'),
      );

      await pump(tester, const NewJournalEntrySheet(caseId: 'c1'));

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
      await pump(tester, const NewJournalEntrySheet(caseId: 'c1'));

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      verifyNever(() => journal.createWithFiles(any(), any()));
      expect(find.text('This field is required'), findsOneWidget);
    });
  });
}
