import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/admission_reasons_providers.dart';
import 'package:federfall/features/cases/edit_case_intake_sheet.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart' hide Finder;
import 'package:mocktail/mocktail.dart';

class MockCasesRepo extends Mock implements PbCasesRepository {}

const _testCase = Case(
  id: 'c1',
  animal: 'a1',
  admissionReasons: ['adre1'],
  intakeWeightG: 250,
);

Future<void> _open(
  WidgetTester tester,
  PbCasesRepository repo, {
  Case medicalCase = _testCase,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        casesRepositoryProvider.overrideWith((ref) async => repo),
        admissionReasonsProvider.overrideWith(
          (ref) async => const [AdmissionReason(id: 'adre1', label: 'Injury')],
        ),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () => showEditCaseIntakeSheet(ctx, medicalCase),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => registerFallbackValue(<String, dynamic>{}));

  testWidgets('opens prefilled and saves edited intake fields',
      (tester) async {
    final repo = MockCasesRepo();
    when(() => repo.update(any(), any())).thenAnswer(
      (_) async => _testCase,
    );

    await _open(tester, repo);

    expect(find.text('Edit intake'), findsOneWidget);
    // Weight is no longer an intake field — it lives in the weights trend.
    expect(
      find.widgetWithText(TextFormField, 'Intake weight (g)'),
      findsNothing,
    );

    final save = find.widgetWithText(FilledButton, 'Save');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();

    final data =
        verify(() => repo.update('c1', captureAny())).captured.single
            as Map<String, dynamic>;
    expect(data.containsKey('intake_weight_g'), isFalse);
    expect(data['admission_reasons'], ['adre1']);
  });

  testWidgets('blocks saving when found date is after the admission date',
      (tester) async {
    final repo = MockCasesRepo();
    await _open(
      tester,
      repo,
      medicalCase: Case(
        id: 'c1',
        animal: 'a1',
        admissionReasons: const ['adre1'],
        foundAt: DateTime(2026, 1, 10),
        admittedAt: DateTime(2026, 1, 5),
      ),
    );

    final save = find.widgetWithText(FilledButton, 'Save');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(
      find.text('The found date cannot be after the admission date'),
      findsOneWidget,
    );
    verifyNever(() => repo.update(any(), any()));
  });

  testWidgets('blocks saving when no admission reason is selected',
      (tester) async {
    final repo = MockCasesRepo();
    await _open(tester, repo);

    // Deselect the only reason, then try to save.
    await tester.tap(find.widgetWithText(FilterChip, 'Injury'));
    await tester.pumpAndSettle();
    final save = find.widgetWithText(FilledButton, 'Save');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();

    verifyNever(() => repo.update(any(), any()));
  });
}
