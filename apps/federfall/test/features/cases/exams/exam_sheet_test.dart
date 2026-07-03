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

void main() {
  setUpAll(() => registerFallbackValue(<String, dynamic>{}));

  late MockExamsRepo exams;

  setUp(() {
    exams = MockExamsRepo();
    when(() => exams.saveWithFindings(any())).thenAnswer((_) async => 'e1');
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
    final container = ProviderContainer(
      overrides: [
        currentUserProvider.overrideWith(
          (ref) async =>
              const AppUser(id: 'u1', email: 'me@x.org', org: 'org1'),
        ),
        examsRepositoryProvider.overrideWith((ref) async => exams),
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

  Future<void> save(WidgetTester tester) async {
    final save = find.widgetWithText(FilledButton, 'Save');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
  }

  testWidgets('saves vitals + findings in ONE atomic call', (tester) async {
    await pump(tester, const ExamSheet(caseId: 'c1', animalId: 'a1'));

    // Body condition 3, hydration moderate; leave everything else untouched.
    await tester.tap(find.text('3'));
    await tester.tap(find.text('Moderate'));
    await tester.pumpAndSettle();
    await save(tester);

    final body =
        verify(() => exams.saveWithFindings(captureAny())).captured.single
            as Map<String, dynamic>;
    expect(body['id'], isNull);
    expect(body['case'], 'c1');
    expect(body['animal'], 'a1');
    final exam = body['exam'] as Map<String, dynamic>;
    expect(exam['body_condition'], 3);
    expect(exam['hydration'], 'moderate');
    // A vitals-only exam sends an empty findings set.
    expect(body['findings'], isEmpty);
    expect(body.containsKey('weight_g'), isFalse);
  });

  testWidgets('edit sends the exam id and the full findings set', (
    tester,
  ) async {
    const existing = Exam(
      id: 'e1',
      caseId: 'c1',
      animal: 'a1',
      bodyCondition: 2,
    );
    const findings = [
      ExamFinding(
        id: 'f1',
        exam: 'e1',
        system: BodySystem.eyes,
        status: FindingStatus.abnormal,
        note: 'cloudy',
      ),
    ];

    await pump(
      tester,
      const ExamSheet(
        caseId: 'c1',
        animalId: 'a1',
        exam: existing,
        findings: findings,
      ),
    );
    await save(tester);

    final body =
        verify(() => exams.saveWithFindings(captureAny())).captured.single
            as Map<String, dynamic>;
    expect(body['id'], 'e1');
    // create-only keys stay out of an update payload
    expect(body.containsKey('case'), isFalse);
    expect(body.containsKey('animal'), isFalse);
    final sent = body['findings'] as List<dynamic>;
    expect(sent, hasLength(1));
    expect(
      sent.single,
      {'system': 'eyes', 'status': 'abnormal', 'note': 'cloudy'},
    );
  });
}
