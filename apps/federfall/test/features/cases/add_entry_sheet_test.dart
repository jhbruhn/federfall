import 'package:federfall/features/animals/custody_providers.dart';
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
    bool holdsBird = true,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dispositionsForCaseProvider('c1').overrideWith(
            (ref) async => dispositions,
          ),
          // Weight, egg and marking are animal-scoped and follow custody
          // (1700000079), which case access does not imply — stated here so the
          // assertions below are not silently checking disabled entries.
          canWriteAnimalProvider('a1').overrideWith((ref) async => holdsBird),
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
    expect(find.text('Handoff / move'), findsOneWidget);
  });

  testWidgets('offers placement once, not split into move and handoff', (
    tester,
  ) async {
    await open(tester);

    // Both used to open the same form, one of them with the carer field
    // hidden — and that field is the distinction (federfall-0se6).
    expect(find.text('Handoff / move'), findsOneWidget);
    expect(find.text('Hand off to carer'), findsNothing);
    expect(find.text('Log location / move'), findsNothing);
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

  ListTile kindTile(WidgetTester tester, String label) =>
      tester.widget<ListTile>(find.widgetWithText(ListTile, label));

  testWidgets("the animal-scoped kinds are enabled for the bird's holder", (
    tester,
  ) async {
    await open(tester);

    expect(kindTile(tester, 'Add weight').enabled, isTrue);
    expect(kindTile(tester, 'Add egg laid').enabled, isTrue);
    expect(kindTile(tester, 'Add marking').enabled, isTrue);
  });

  // The divergence this gating exists for: the carer of a DISPOSED case may
  // still write its journal, but the bird has moved on, so a weight or a ring
  // on it would 403. Case-scoped kinds beside them stay live.
  testWidgets('they go inert once the bird is no longer held', (tester) async {
    await open(tester, holdsBird: false);

    expect(kindTile(tester, 'Add weight').enabled, isFalse);
    expect(kindTile(tester, 'Add egg laid').enabled, isFalse);
    expect(kindTile(tester, 'Add marking').enabled, isFalse);
    expect(kindTile(tester, 'Add note').enabled, isTrue);
    expect(kindTile(tester, 'Exam').enabled, isTrue);
  });
}
