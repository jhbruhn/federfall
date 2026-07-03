import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/follow_ups/follow_up_sheet.dart';
import 'package:federfall/features/cases/follow_ups/follow_up_tile.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockFollowUpsRepo extends Mock implements PbFollowUpsRepository {}

void main() {
  setUpAll(() => registerFallbackValue(<String, dynamic>{}));

  late MockFollowUpsRepo followUps;

  setUp(() {
    followUps = MockFollowUpsRepo();
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
    final container = ProviderContainer(
      overrides: [
        currentUserProvider.overrideWith(
          (ref) async =>
              const AppUser(id: 'u1', email: 'me@x.org', org: 'org1'),
        ),
        followUpsRepositoryProvider.overrideWith((ref) async => followUps),
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

  group('FollowUpSheet', () {
    testWidgets('schedules a recheck with a note', (tester) async {
      when(() => followUps.create(any())).thenAnswer(
        (_) async => const FollowUp(id: 'f1', caseId: 'c1'),
      );

      await pump(tester, const FollowUpSheet(caseId: 'c1'));
      await tester.enterText(find.byType(TextFormField), 'Check the wing');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final body =
          verify(() => followUps.create(captureAny())).captured.single
              as Map<String, dynamic>;
      expect(body['case'], 'c1');
      expect(body['created_by'], 'u1');
      expect(body['org'], 'org1');
      expect(body['note'], 'Check the wing');
    });

    testWidgets('editing an existing recheck updates it', (tester) async {
      when(() => followUps.update('f1', any())).thenAnswer(
        (_) async => const FollowUp(id: 'f1', caseId: 'c1'),
      );

      await pump(
        tester,
        FollowUpSheet(
          caseId: 'c1',
          followUp: FollowUp(
            id: 'f1',
            caseId: 'c1',
            dueAt: DateTime(2026, 2),
            note: 'Check the wing',
          ),
        ),
      );

      expect(find.text('Check the wing'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final body =
          verify(() => followUps.update('f1', captureAny())).captured.single
              as Map<String, dynamic>;
      expect(body['note'], 'Check the wing');
      expect(body.containsKey('case'), isFalse);
    });
  });

  group('FollowUpTile', () {
    testWidgets('shows an overdue chip and can be marked done', (
      tester,
    ) async {
      when(() => followUps.update('f1', any())).thenAnswer(
        (_) async => const FollowUp(id: 'f1', caseId: 'c1'),
      );

      await pump(
        tester,
        FollowUpTile(
          caseId: 'c1',
          followUp: FollowUp(
            id: 'f1',
            caseId: 'c1',
            dueAt: DateTime(2000),
            note: 'Check the wing',
          ),
        ),
      );

      expect(find.text('Check the wing'), findsOneWidget);
      expect(find.textContaining('Overdue by'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mark done'));
      await tester.pumpAndSettle();

      final body =
          verify(() => followUps.update('f1', captureAny())).captured.single
              as Map<String, dynamic>;
      expect(body.containsKey('done_at'), isTrue);
      expect(body['done_at'], isNot(''));
    });

    testWidgets('deletes after confirming', (tester) async {
      when(() => followUps.delete('f1')).thenAnswer((_) async {});

      await pump(
        tester,
        const FollowUpTile(
          caseId: 'c1',
          followUp: FollowUp(id: 'f1', caseId: 'c1'),
        ),
      );

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Delete this recheck?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();

      verify(() => followUps.delete('f1')).called(1);
    });
  });
}
