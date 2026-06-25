import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/exams/exam_sheet.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockExamsRepo extends Mock implements PbExamsRepository {}

class MockExamFindingsRepo extends Mock implements PbExamFindingsRepository {}

void main() {
  setUpAll(() => registerFallbackValue(<String, dynamic>{}));

  late MockExamsRepo exams;
  late MockExamFindingsRepo findings;

  setUp(() {
    exams = MockExamsRepo();
    findings = MockExamFindingsRepo();
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
    final container = ProviderContainer(
      overrides: [
        currentUserProvider.overrideWith(
          (ref) async =>
              const AppUser(id: 'u1', email: 'me@x.org', org: 'org1'),
        ),
        examsRepositoryProvider.overrideWith((ref) async => exams),
        examFindingsRepositoryProvider.overrideWith((ref) async => findings),
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

  testWidgets('saves the assessed vitals; no findings when none assessed',
      (tester) async {
    when(() => exams.create(any())).thenAnswer(
      (_) async => const Exam(id: 'e1', caseId: 'c1', animal: 'a1'),
    );

    await pump(tester, const ExamSheet(caseId: 'c1', animalId: 'a1'));

    // Body condition 3, hydration moderate; leave everything else untouched.
    await tester.tap(find.text('3'));
    await tester.tap(find.text('Moderate'));
    await tester.pumpAndSettle();
    final save = find.widgetWithText(FilledButton, 'Save');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    final body = verify(() => exams.create(captureAny())).captured.single
        as Map<String, dynamic>;
    expect(body['case'], 'c1');
    expect(body['animal'], 'a1');
    expect(body['examiner'], 'u1');
    expect(body['org'], 'org1');
    expect(body['body_condition'], 3);
    expect(body['hydration'], 'moderate');
    // A vitals-only exam writes no by-system rows.
    verifyNever(() => findings.create(any()));
  });
}
