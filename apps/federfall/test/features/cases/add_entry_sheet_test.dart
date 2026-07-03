import 'package:federfall/features/cases/add_entry_sheet.dart';
import 'package:federfall/features/cases/disposition/disposition_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_models/federfall_models.dart' hide Finder;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const medicalCase = Case(id: 'c1', animal: 'a1');

  Future<void> open(
    WidgetTester tester, {
    List<Disposition> dispositions = const [],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dispositionsForCaseProvider('c1').overrideWith(
            (ref) async => dispositions,
          ),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () =>
                      showAddEntrySheet(context, medicalCase: medicalCase),
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

  testWidgets('shows the kinds grouped under section headers', (tester) async {
    await open(tester);

    // Group headers (rendered upper-cased).
    expect(find.text('CLINICAL'), findsOneWidget);
    expect(find.text('MEDICATION'), findsOneWidget);
    expect(find.text('MOVEMENT'), findsOneWidget);
    expect(find.text('LIFECYCLE'), findsOneWidget);

    // A sample of the kinds across groups.
    expect(find.text('Add note'), findsOneWidget);
    expect(find.text('Exam'), findsOneWidget);
    expect(find.text('Log dose'), findsOneWidget);
    expect(find.text('Hand off to carer'), findsOneWidget);
  });

  ListTile outcomeTile(WidgetTester tester) =>
      tester.widget<ListTile>(find.widgetWithText(ListTile, 'Record outcome'));

  testWidgets('offers an enabled outcome action on a live case', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('Record outcome'), findsOneWidget);
    expect(outcomeTile(tester).enabled, isTrue);
  });

  testWidgets('keeps the outcome action visible but disabled once disposed', (
    tester,
  ) async {
    await open(
      tester,
      dispositions: const [
        Disposition(id: 'd1', caseId: 'c1', type: DispositionType.released),
      ],
    );
    // Still present (layout/muscle memory preserved) but inert.
    expect(find.text('Record outcome'), findsOneWidget);
    expect(outcomeTile(tester).enabled, isFalse);
    // The rest of the sheet still works.
    expect(find.text('Add note'), findsOneWidget);
  });
}
