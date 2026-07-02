import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/aviaries/aviaries_providers.dart';
import 'package:federfall/features/cases/disposition/disposition_sheet.dart';
import 'package:federfall/features/cases/disposition/disposition_tile.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockDispositionsRepo extends Mock implements PbDispositionsRepository {}

void main() {
  setUpAll(() => registerFallbackValue(<String, dynamic>{}));

  late MockDispositionsRepo dispositions;

  setUp(() {
    dispositions = MockDispositionsRepo();
  });

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    List<Aviary> aviaries = const [],
  }) async {
    final container = ProviderContainer(
      overrides: [
        currentUserProvider.overrideWith(
          (ref) async =>
              const AppUser(id: 'u1', email: 'me@x.org', org: 'org1'),
        ),
        dispositionsRepositoryProvider
            .overrideWith((ref) async => dispositions),
        activeAviariesProvider.overrideWith((ref) async => aviaries),
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

  group('DispositionSheet', () {
    testWidgets('records a death outcome with the carer as performer',
        (tester) async {
      when(() => dispositions.create(any())).thenAnswer(
        (_) async => const Disposition(
          id: 'd1',
          caseId: 'c1',
          type: DispositionType.died,
        ),
      );

      await pump(tester, const DispositionSheet(caseId: 'c1'));

      // Default type is "Released"; switch to "Died".
      await tester.tap(find.text('Released'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Died').last);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Record outcome'));
      await tester.pumpAndSettle();

      final body = verify(() => dispositions.create(captureAny()))
          .captured
          .single as Map<String, dynamic>;
      expect(body['case'], 'c1');
      expect(body['type'], 'died');
      expect(body['performed_by'], 'u1');
      expect(body['org'], 'org1');
    });

    testWidgets('editing an existing outcome updates it', (tester) async {
      when(() => dispositions.update(any(), any())).thenAnswer(
        (_) async => const Disposition(
          id: 'd1',
          caseId: 'c1',
          type: DispositionType.released,
        ),
      );

      await pump(
        tester,
        const DispositionSheet(
          caseId: 'c1',
          disposition: Disposition(
            id: 'd1',
            caseId: 'c1',
            type: DispositionType.released,
            reason: 'fit to fly',
          ),
        ),
      );

      // Prefilled in edit mode.
      expect(find.text('Edit outcome'), findsOneWidget);
      expect(find.text('fit to fly'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Record outcome'));
      await tester.pumpAndSettle();

      verify(() => dispositions.update('d1', any())).called(1);
      verifyNever(() => dispositions.create(any()));
    });

    testWidgets('deleting an outcome confirms and calls delete',
        (tester) async {
      when(() => dispositions.delete(any())).thenAnswer((_) async {});

      await pump(
        tester,
        const DispositionSheet(
          caseId: 'c1',
          disposition: Disposition(
            id: 'd1',
            caseId: 'c1',
            type: DispositionType.released,
          ),
        ),
      );

      await tester.ensureVisible(
        find.widgetWithText(TextButton, 'Delete outcome'),
      );
      await tester.tap(find.widgetWithText(TextButton, 'Delete outcome'));
      await tester.pumpAndSettle();
      // Confirm in the dialog.
      await tester.tap(find.widgetWithText(TextButton, 'Delete outcome').last);
      await tester.pumpAndSettle();

      verify(() => dispositions.delete('d1')).called(1);
    });

    testWidgets('placed in aviary records the chosen aviary (FED-4.12)',
        (tester) async {
      when(() => dispositions.create(any())).thenAnswer(
        (_) async => const Disposition(
          id: 'd1',
          caseId: 'c1',
          type: DispositionType.placedInAviary,
        ),
      );

      await pump(
        tester,
        const DispositionSheet(caseId: 'c1'),
        aviaries: const [Aviary(id: 'av1', name: 'Garden aviary')],
      );

      await tester.tap(find.text('Released'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Placed in aviary').last);
      await tester.pumpAndSettle();

      // Pick the aviary from the now-visible picker.
      await tester.tap(find.text('Aviary'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Garden aviary').last);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Record outcome'));
      await tester.pumpAndSettle();

      final body = verify(() => dispositions.create(captureAny()))
          .captured
          .single as Map<String, dynamic>;
      expect(body['type'], 'placed_in_aviary');
      expect(body['aviary'], 'av1');
    });

    testWidgets('release shows the location field', (tester) async {
      await pump(tester, const DispositionSheet(caseId: 'c1'));

      // Default is Released → release-specific fields are visible.
      expect(find.text('Release location'), findsOneWidget);
      expect(find.text('Release type'), findsOneWidget);
    });

    testWidgets('euthanasia records the performing vet, not a sign-off flag',
        (tester) async {
      when(() => dispositions.create(any())).thenAnswer(
        (_) async => const Disposition(
          id: 'd1',
          caseId: 'c1',
          type: DispositionType.euthanized,
        ),
      );

      await pump(tester, const DispositionSheet(caseId: 'c1'));
      await tester.tap(find.text('Released'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Euthanized').last);
      await tester.pumpAndSettle();

      // No sign-off toggle for euthanasia; a vet-name field instead.
      expect(find.text('Vet signed off'), findsNothing);
      await tester.enterText(
        find.ancestor(
          of: find.text('Performed by (vet)'),
          matching: find.byType(TextField),
        ),
        'Dr. Vogel',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Record outcome'));
      await tester.pumpAndSettle();

      final body = verify(() => dispositions.create(captureAny()))
          .captured
          .single as Map<String, dynamic>;
      expect(body['type'], 'euthanized');
      expect(body['vet'], 'Dr. Vogel');
    });
  });

  group('DispositionTile', () {
    testWidgets('shows the outcome label and release detail', (tester) async {
      await pump(
        tester,
        const DispositionTile(
          disposition: Disposition(
            id: 'd1',
            caseId: 'c1',
            type: DispositionType.released,
            releaseLocation: 'Stadtwald',
            vetSignedOff: true,
          ),
        ),
      );

      expect(find.text('Released'), findsOneWidget);
      expect(find.text('Stadtwald'), findsOneWidget);
      expect(find.text('Vet signed off'), findsOneWidget);
    });
  });
}
