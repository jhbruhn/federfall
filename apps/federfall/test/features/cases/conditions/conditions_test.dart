import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/conditions/condition_entry_sheet.dart';
import 'package:federfall/features/cases/conditions/condition_entry_tile.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockConditionsRepo extends Mock implements PbConditionsRepository {}

class MockCaseConditionsRepo extends Mock
    implements PbCaseConditionsRepository {}

void main() {
  setUpAll(() => registerFallbackValue(<String, dynamic>{}));

  late MockConditionsRepo conditions;
  late MockCaseConditionsRepo caseConditions;

  const codeList = [
    Condition(id: 'c1', label: 'Fraktur (Knochenbruch)'),
    Condition(id: 'c2', label: 'Paramyxovirose (PMV)', isNotifiable: true),
  ];

  setUp(() {
    conditions = MockConditionsRepo();
    caseConditions = MockCaseConditionsRepo();
    when(
      () => conditions.list(
        filter: any(named: 'filter'),
        sort: any(named: 'sort'),
        expand: any(named: 'expand'),
      ),
    ).thenAnswer((_) async => codeList);
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
    final container = ProviderContainer(
      overrides: [
        currentUserProvider.overrideWith(
          (ref) async =>
              const AppUser(id: 'u1', email: 'me@x.org', org: 'org1'),
        ),
        conditionsRepositoryProvider.overrideWith((ref) async => conditions),
        caseConditionsRepositoryProvider.overrideWith(
          (ref) async => caseConditions,
        ),
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
    // Drop focus so the autocomplete options overlay closes before tapping.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final submit = find.widgetWithText(FilledButton, 'Save');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
  }

  group('ConditionEntrySheet', () {
    testWidgets('stores a code-list match as a condition relation', (
      tester,
    ) async {
      when(() => caseConditions.create(any())).thenAnswer(
        (_) async => const CaseCondition(id: 'x', caseId: 'c1'),
      );

      await pump(tester, const ConditionEntrySheet(caseId: 'c1'));
      await tester.enterText(
        find.byType(TextField).first,
        'Fraktur (Knochenbruch)',
      );
      await save(tester);

      final body =
          verify(() => caseConditions.create(captureAny())).captured.single
              as Map<String, dynamic>;
      expect(body['condition'], 'c1');
      expect(body['free_text'], '');
      expect(body['certainty'], 'suspected');
      expect(body['org'], 'org1');
    });

    testWidgets('stores an unmatched entry as free text', (tester) async {
      when(() => caseConditions.create(any())).thenAnswer(
        (_) async => const CaseCondition(id: 'x', caseId: 'c1'),
      );

      await pump(tester, const ConditionEntrySheet(caseId: 'c1'));
      await tester.enterText(find.byType(TextField).first, 'Schnupfen');
      await save(tester);

      final body =
          verify(() => caseConditions.create(captureAny())).captured.single
              as Map<String, dynamic>;
      expect(body['condition'], isNull);
      expect(body['free_text'], 'Schnupfen');
    });

    testWidgets('requires a condition', (tester) async {
      await pump(tester, const ConditionEntrySheet(caseId: 'c1'));
      await save(tester);

      verifyNever(() => caseConditions.create(any()));
      expect(find.text('This field is required'), findsOneWidget);
    });
  });

  group('ConditionEntryTile', () {
    testWidgets('shows the label, certainty and a notifiable badge', (
      tester,
    ) async {
      await pump(
        tester,
        const ConditionEntryTile(
          entry: CaseCondition(
            id: 'x',
            caseId: 'c1',
            condition: 'c2',
            certainty: Certainty.confirmed,
          ),
          caseId: 'c1',
        ),
      );

      expect(find.text('Paramyxovirose (PMV)'), findsOneWidget);
      expect(find.text('Confirmed'), findsOneWidget);
      expect(find.text('Notifiable'), findsOneWidget);
    });

    testWidgets('deletes a diagnosis after confirmation', (tester) async {
      when(() => caseConditions.delete('x')).thenAnswer((_) async {});

      await pump(
        tester,
        const ConditionEntryTile(
          entry: CaseCondition(id: 'x', caseId: 'c1', freeText: 'Schnupfen'),
          caseId: 'c1',
        ),
      );

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();

      verify(() => caseConditions.delete('x')).called(1);
    });
  });
}
