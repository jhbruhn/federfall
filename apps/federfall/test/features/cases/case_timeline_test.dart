import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/case_timeline.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockJournalRepo extends Mock implements PbJournalRepository {}

class MockWeightsRepo extends Mock implements PbWeightsRepository {}

void main() {
  late MockJournalRepo journal;
  late MockWeightsRepo weights;

  setUp(() {
    journal = MockJournalRepo();
    weights = MockWeightsRepo();
    when(() => weights.forCase(any())).thenAnswer((_) async => []);
  });

  Future<void> pump(WidgetTester tester, Case medicalCase) async {
    final container = ProviderContainer(
      overrides: [
        journalRepositoryProvider.overrideWith((ref) async => journal),
        weightsRepositoryProvider.overrideWith((ref) async => weights),
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
          home: Scaffold(
            body: SingleChildScrollView(
              child: CaseTimeline(medicalCase: medicalCase),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('interleaves journal entries and milestones newest-first',
      (tester) async {
    when(() => journal.forCase('c1')).thenAnswer(
      (_) async => [
        JournalEntry(
          id: 'j1',
          caseId: 'c1',
          text: 'Mid entry',
          entryAt: DateTime.utc(2026, 6, 21),
        ),
      ],
    );

    final medicalCase = Case(
      id: 'c1',
      animal: 'a1',
      admittedAt: DateTime.utc(2026, 6, 20),
      created: DateTime.utc(2026, 6, 22),
    );
    await pump(tester, medicalCase);

    // All three live in one list (not split into Journal vs Timeline).
    expect(find.text('Case opened'), findsOneWidget); // 06-22, newest
    expect(find.text('Mid entry'), findsOneWidget); // 06-21
    expect(find.text('Admitted'), findsOneWidget); // 06-20, oldest

    // Verify the vertical order: opened above the journal entry above admitted.
    final opened = tester.getTopLeft(find.text('Case opened')).dy;
    final entry = tester.getTopLeft(find.text('Mid entry')).dy;
    final admitted = tester.getTopLeft(find.text('Admitted')).dy;
    expect(opened, lessThan(entry));
    expect(entry, lessThan(admitted));
  });

  testWidgets('places weight measurements on the timeline', (tester) async {
    when(() => journal.forCase('c1')).thenAnswer((_) async => []);
    when(() => weights.forCase('c1')).thenAnswer(
      (_) async => [
        Weight(
          id: 'w1',
          caseId: 'c1',
          weightG: 248,
          measuredAt: DateTime.utc(2026, 6, 21),
        ),
      ],
    );

    await pump(tester, const Case(id: 'c1', animal: 'a1'));

    expect(find.text('248 g'), findsOneWidget);
  });

  testWidgets('shows the empty state when nothing is on the timeline',
      (tester) async {
    when(() => journal.forCase('c1')).thenAnswer((_) async => []);

    await pump(tester, const Case(id: 'c1', animal: 'a1'));

    expect(find.text('No entries yet'), findsOneWidget);
  });
}
