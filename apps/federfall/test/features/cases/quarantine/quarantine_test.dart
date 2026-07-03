import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/quarantine/quarantine_sheet.dart';
import 'package:federfall/features/cases/quarantine/quarantine_tile.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockQuarantineRepo extends Mock implements PbQuarantineRepository {}

void main() {
  setUpAll(() => registerFallbackValue(<String, dynamic>{}));

  late MockQuarantineRepo quarantine;

  setUp(() {
    quarantine = MockQuarantineRepo();
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
    final container = ProviderContainer(
      overrides: [
        currentUserProvider.overrideWith(
          (ref) async =>
              const AppUser(id: 'u1', email: 'me@x.org', org: 'org1'),
        ),
        quarantineRepositoryProvider.overrideWith((ref) async => quarantine),
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

  testWidgets('imposing quarantine records case, imposer and org', (
    tester,
  ) async {
    when(() => quarantine.create(any())).thenAnswer(
      (_) async => const Quarantine(id: 'q1', caseId: 'c1'),
    );

    await pump(tester, const QuarantineSheet(caseId: 'c1'));
    await tester.enterText(find.byType(TextField), 'Suspected PMV');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final body =
        verify(() => quarantine.create(captureAny())).captured.single
            as Map<String, dynamic>;
    expect(body['case'], 'c1');
    expect(body['set_by'], 'u1');
    expect(body['org'], 'org1');
    expect(body['reason'], 'Suspected PMV');
  });

  testWidgets('editing an existing entry updates it and prefills the reason', (
    tester,
  ) async {
    when(() => quarantine.update('q1', any())).thenAnswer(
      (_) async => const Quarantine(id: 'q1', caseId: 'c1'),
    );

    await pump(
      tester,
      QuarantineSheet(
        caseId: 'c1',
        entry: Quarantine(
          id: 'q1',
          caseId: 'c1',
          setAt: DateTime(2026),
          until: DateTime(2026, 1, 15),
          reason: 'Suspected PMV',
        ),
      ),
    );

    expect(find.text('Suspected PMV'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final body =
        verify(() => quarantine.update('q1', captureAny())).captured.single
            as Map<String, dynamic>;
    expect(body['reason'], 'Suspected PMV');
    expect(body.containsKey('case'), isFalse);
  });

  testWidgets('rejects an end date before the start date', (tester) async {
    await pump(
      tester,
      QuarantineSheet(
        caseId: 'c1',
        entry: Quarantine(
          id: 'q1',
          caseId: 'c1',
          setAt: DateTime(2026, 1, 20),
          until: DateTime(2026, 1, 15),
        ),
      ),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    verifyNever(() => quarantine.update(any(), any()));
    expect(
      find.text('The end date cannot be before the start date'),
      findsOneWidget,
    );
  });

  group('QuarantineTile', () {
    testWidgets('shows the ended marker for a lapsed phase', (tester) async {
      await pump(
        tester,
        QuarantineTile(
          caseId: 'c1',
          phase: QuarantinePhase.ended,
          entry: Quarantine(
            id: 'q1',
            caseId: 'c1',
            until: DateTime(2026),
          ),
        ),
      );

      expect(find.text('Quarantine ended'), findsOneWidget);
    });

    testWidgets(
      'shows the reason and an end-now shortcut for the active period',
      (tester) async {
        when(() => quarantine.update('q1', any())).thenAnswer(
          (_) async => const Quarantine(id: 'q1', caseId: 'c1'),
        );

        await pump(
          tester,
          QuarantineTile(
            caseId: 'c1',
            isCurrent: true,
            entry: Quarantine(
              id: 'q1',
              caseId: 'c1',
              until: DateTime(2100),
              reason: 'Suspected PMV',
            ),
          ),
        );

        expect(find.text('Suspected PMV'), findsOneWidget);
        await tester.tap(find.text('End quarantine'));
        await tester.pumpAndSettle();

        final body =
            verify(() => quarantine.update('q1', captureAny())).captured.single
                as Map<String, dynamic>;
        expect(body.containsKey('quarantine_until'), isTrue);
      },
    );

    testWidgets('hides the end-now shortcut once already ended', (
      tester,
    ) async {
      await pump(
        tester,
        QuarantineTile(
          caseId: 'c1',
          isCurrent: true,
          entry: Quarantine(id: 'q1', caseId: 'c1', until: DateTime(2000)),
        ),
      );

      expect(find.text('End quarantine'), findsNothing);
    });

    testWidgets('deletes after confirming from the menu', (tester) async {
      when(() => quarantine.delete('q1')).thenAnswer((_) async {});

      await pump(
        tester,
        const QuarantineTile(
          caseId: 'c1',
          entry: Quarantine(id: 'q1', caseId: 'c1'),
        ),
      );

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Delete quarantine?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();

      verify(() => quarantine.delete('q1')).called(1);
    });
  });
}
