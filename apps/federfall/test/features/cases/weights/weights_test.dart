import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/weights/weight_entry_sheet.dart';
import 'package:federfall/features/cases/weights/weight_entry_tile.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockWeightsRepo extends Mock implements PbWeightsRepository {}

void main() {
  setUpAll(() => registerFallbackValue(<String, dynamic>{}));

  late MockWeightsRepo weights;

  setUp(() {
    weights = MockWeightsRepo();
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
    final container = ProviderContainer(
      overrides: [
        currentUserProvider.overrideWith(
          (ref) async =>
              const AppUser(id: 'u1', email: 'me@x.org', org: 'org1'),
        ),
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
          home: Scaffold(body: child),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('WeightEntrySheet', () {
    testWidgets('saves a measurement, parsing a comma decimal',
        (tester) async {
      when(() => weights.create(any())).thenAnswer(
        (_) async => const Weight(id: 'w1', caseId: 'c1', weightG: 248.5),
      );

      await pump(tester, const WeightEntrySheet(caseId: 'c1'));

      await tester.enterText(find.byType(TextField).first, '248,5');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final body = verify(() => weights.create(captureAny())).captured.single
          as Map<String, dynamic>;
      expect(body['case'], 'c1');
      expect(body['weight_g'], 248.5);
      expect(body['author'], 'u1');
      expect(body['org'], 'org1');
    });

    testWidgets('rejects a non-positive weight', (tester) async {
      await pump(tester, const WeightEntrySheet(caseId: 'c1'));

      await tester.enterText(find.byType(TextField).first, '0');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      verifyNever(() => weights.create(any()));
      expect(find.text('Enter a weight greater than zero'), findsOneWidget);
    });
  });

  group('WeightEntryTile', () {
    testWidgets('renders the formatted weight', (tester) async {
      await pump(
        tester,
        const WeightEntryTile(
          weight: Weight(id: 'w1', caseId: 'c1', weightG: 248),
          caseId: 'c1',
        ),
      );

      expect(find.text('248 g'), findsOneWidget);
    });

    testWidgets('deletes a measurement after confirmation', (tester) async {
      when(() => weights.delete('w1')).thenAnswer((_) async {});

      await pump(
        tester,
        const WeightEntryTile(
          weight: Weight(id: 'w1', caseId: 'c1', weightG: 248),
          caseId: 'c1',
        ),
      );

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();

      verify(() => weights.delete('w1')).called(1);
    });
  });
}
