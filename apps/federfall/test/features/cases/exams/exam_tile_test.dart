import 'package:federfall/features/cases/exams/exam_tile.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_models/federfall_models.dart' hide Finder;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required Exam exam,
    List<ExamFinding> findings = const [],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ExamTile(
              exam: exam,
              findings: findings,
              caseId: 'c1',
              animalId: 'a1',
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  // A labelled fact is rendered as Text.rich (label + value in separate spans),
  // so match on the combined plain text of the RichText carrying both.
  Finder factContaining(String label, String value) => find.byWidgetPredicate(
    (w) =>
        w is RichText &&
        w.text.toPlainText().contains(label) &&
        w.text.toPlainText().contains(value),
  );

  testWidgets('renders each vital on its own labelled line', (tester) async {
    await pump(
      tester,
      exam: Exam(
        id: 'e1',
        caseId: 'c1',
        animal: 'a1',
        examinedAt: DateTime(2026, 3, 4),
        bodyCondition: 2,
        temperature: 41.3,
        hydration: Hydration.moderate,
        mentation: Mentation.quiet,
      ),
    );

    expect(factContaining('Body condition', '2/5'), findsOneWidget);
    expect(factContaining('Temp', '41.3'), findsOneWidget);
    expect(factContaining('Hydration', 'Moderate'), findsOneWidget);
    expect(factContaining('Attitude', 'Quiet'), findsOneWidget);
  });

  testWidgets('shows abnormal findings with their note and lists normals', (
    tester,
  ) async {
    await pump(
      tester,
      exam: const Exam(id: 'e1', caseId: 'c1', animal: 'a1'),
      findings: const [
        ExamFinding(
          id: 'f1',
          exam: 'e1',
          system: BodySystem.wings,
          status: FindingStatus.abnormal,
          note: 'left wing droop',
        ),
        ExamFinding(
          id: 'f2',
          exam: 'e1',
          system: BodySystem.eyes,
          status: FindingStatus.normal,
        ),
      ],
    );

    expect(factContaining('Wings', 'left wing droop'), findsOneWidget);
    expect(find.textContaining('Eyes'), findsOneWidget);
  });

  testWidgets('shows free-text notes (previously dropped)', (tester) async {
    await pump(
      tester,
      exam: const Exam(
        id: 'e1',
        caseId: 'c1',
        animal: 'a1',
        notes: 'Bird is bright and alert, eating well.',
      ),
    );

    expect(
      find.text('Bird is bright and alert, eating well.'),
      findsOneWidget,
    );
  });

  testWidgets('falls back to "no vitals" when none recorded', (tester) async {
    await pump(
      tester,
      exam: const Exam(id: 'e1', caseId: 'c1', animal: 'a1'),
    );

    expect(find.text('No vitals recorded'), findsOneWidget);
  });

  testWidgets('hides body condition and temperature when stored as 0', (
    tester,
  ) async {
    // PocketBase stores unset numeric fields as 0; never surface "0/5"/"0.0".
    await pump(
      tester,
      exam: const Exam(
        id: 'e1',
        caseId: 'c1',
        animal: 'a1',
        bodyCondition: 0,
        temperature: 0,
        hydration: Hydration.normal,
      ),
    );

    expect(factContaining('Body condition', '0/5'), findsNothing);
    expect(factContaining('Temp', '0.0'), findsNothing);
    // A genuinely-set vital still shows, so the row is not "no vitals".
    expect(factContaining('Hydration', 'Normal'), findsOneWidget);
    expect(find.text('No vitals recorded'), findsNothing);
  });
}
