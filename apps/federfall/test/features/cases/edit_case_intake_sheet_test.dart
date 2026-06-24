import 'package:federfall/data/repository_providers.dart';
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
  reasonsForAdmission: [AdmissionReason.injury],
  intakeWeightG: 250,
);

Future<void> _open(WidgetTester tester, PbCasesRepository repo) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        casesRepositoryProvider.overrideWith((ref) async => repo),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () => showEditCaseIntakeSheet(ctx, _testCase),
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

    // Prefilled with the existing weight.
    expect(find.text('Edit intake'), findsOneWidget);
    final weightField =
        find.widgetWithText(TextFormField, 'Intake weight (g)');
    expect(
      tester.widget<TextFormField>(weightField).controller?.text,
      '250',
    );

    await tester.enterText(weightField, '300');
    final save = find.widgetWithText(FilledButton, 'Save');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();

    final data =
        verify(() => repo.update('c1', captureAny())).captured.single
            as Map<String, dynamic>;
    expect(data['intake_weight_g'], 300);
    expect(data['reasons_for_admission'], ['injury']);
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
