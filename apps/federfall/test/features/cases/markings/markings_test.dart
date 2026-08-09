import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/features/cases/markings/marking_sheet.dart';
import 'package:federfall/features/cases/markings/marking_tile.dart';
import 'package:federfall/features/cases/markings/marking_types_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockMarkingsRepo extends Mock implements PbMarkingsRepository {}

void main() {
  setUpAll(() => registerFallbackValue(<String, dynamic>{}));

  late MockMarkingsRepo markings;

  setUp(() {
    markings = MockMarkingsRepo();
  });

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    Case medicalCase = const Case(id: 'c1', animal: 'a1'),
  }) async {
    final container = ProviderContainer(
      overrides: [
        currentUserProvider.overrideWith(
          (ref) async =>
              const AppUser(id: 'u1', email: 'me@x.org', org: 'org1'),
        ),
        // The sheet reads the case's find moment to date a marking the bird
        // already carried.
        caseByIdProvider('c1').overrideWith((ref) async => medicalCase),
        markingsRepositoryProvider.overrideWith((ref) async => markings),
        markingTypesProvider.overrideWith(
          (ref) async => const [
            MarkingType(id: 'mktp_finder', label: "Finder's ring"),
          ],
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

  testWidgets('applying a marking records animal, case, type and active', (
    tester,
  ) async {
    when(() => markings.create(any())).thenAnswer(
      (_) async => const Marking(
        id: 'm1',
        animal: 'a1',
        type: 'mktp_finder',
      ),
    );

    await pump(
      tester,
      const MarkingSheet(animalId: 'a1', caseId: 'c1'),
    );
    await tester.enterText(find.byType(TextField).first, 'AT-123');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final body =
        verify(() => markings.create(captureAny())).captured.single
            as Map<String, dynamic>;
    expect(body['animal'], 'a1');
    expect(body['applied_in_case'], 'c1');
    expect(body['type'], 'mktp_finder');
    expect(body['code'], 'AT-123');
    expect(body['is_active'], true);
    expect(body['present_at_find'], false);
  });

  group('present when found', () {
    /// The date the sheet would have written, back in local time.
    DateTime appliedAtOf(Map<String, dynamic> body) =>
        DateTime.parse(body['applied_at'] as String).toLocal();

    Future<Map<String, dynamic>> tickAndSave(
      WidgetTester tester, {
      required Case medicalCase,
    }) async {
      when(() => markings.create(any())).thenAnswer(
        (_) async => const Marking(id: 'm1', animal: 'a1', type: 'mktp_finder'),
      );

      await pump(
        tester,
        const MarkingSheet(animalId: 'a1', caseId: 'c1'),
        medicalCase: medicalCase,
      );
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();

      // The find moment owns the date now — picking one would contradict it.
      expect(tester.widget<DateField>(find.byType(DateField)).enabled, isFalse);

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      return verify(() => markings.create(captureAny())).captured.single
          as Map<String, dynamic>;
    }

    testWidgets('dates the marking to the find date and locks the picker', (
      tester,
    ) async {
      final body = await tickAndSave(
        tester,
        medicalCase: Case(
          id: 'c1',
          animal: 'a1',
          foundAt: DateTime(2026, 3, 5),
          admittedAt: DateTime(2026, 3, 2),
        ),
      );

      expect(body['present_at_find'], true);
      expect(appliedAtOf(body), DateTime(2026, 3, 5));
    });

    testWidgets(
      'falls back to the admission when nobody recorded a find date',
      (
        tester,
      ) async {
        final body = await tickAndSave(
          tester,
          medicalCase: Case(
            id: 'c1',
            animal: 'a1',
            admittedAt: DateTime(2026, 3, 2),
          ),
        );

        expect(appliedAtOf(body), DateTime(2026, 3, 2));
      },
    );

    testWidgets('is not offered without a case to anchor to', (tester) async {
      await pump(tester, const MarkingSheet(animalId: 'a1'));

      expect(find.byType(CheckboxListTile), findsNothing);
      expect(tester.widget<DateField>(find.byType(DateField)).enabled, isTrue);
    });

    testWidgets('unticking on an edit gives the marking its own date back', (
      tester,
    ) async {
      when(() => markings.update('m1', any())).thenAnswer(
        (_) async => const Marking(id: 'm1', animal: 'a1', type: 'mktp_finder'),
      );

      await pump(
        tester,
        MarkingSheet(
          animalId: 'a1',
          caseId: 'c1',
          marking: Marking(
            id: 'm1',
            animal: 'a1',
            type: 'mktp_finder',
            appliedAt: DateTime(2026, 3, 5),
            presentAtFind: true,
            isActive: true,
          ),
        ),
        medicalCase: Case(
          id: 'c1',
          animal: 'a1',
          foundAt: DateTime(2026, 3, 5),
        ),
      );

      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      expect(tester.widget<DateField>(find.byType(DateField)).enabled, isTrue);

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final body =
          verify(() => markings.update('m1', captureAny())).captured.single
              as Map<String, dynamic>;
      expect(body['present_at_find'], false);
      expect(appliedAtOf(body), DateTime(2026, 3, 5));
    });
  });

  testWidgets('marking tile shows details and can be marked removed', (
    tester,
  ) async {
    when(() => markings.update('m1', any())).thenAnswer(
      (_) async => const Marking(
        id: 'm1',
        animal: 'a1',
        type: 'mktp_finder',
      ),
    );

    await pump(
      tester,
      const MarkingTile(
        marking: Marking(
          id: 'm1',
          animal: 'a1',
          type: 'mktp_finder',
          code: 'AT-123',
          colour: 'blue',
          isActive: true,
        ),
        caseId: 'c1',
      ),
    );

    expect(find.text("Finder's ring"), findsOneWidget);
    expect(find.text('blue · AT-123'), findsOneWidget);
    // Nothing here says the bird arrived wearing it, because it did not.
    expect(find.text('At find'), findsNothing);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark removed'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Mark removed'));
    await tester.pumpAndSettle();

    final body =
        verify(() => markings.update('m1', captureAny())).captured.single
            as Map<String, dynamic>;
    expect(body['is_active'], false);
    expect(body.containsKey('removed_at'), isTrue);
  });

  testWidgets('a marking the bird arrived wearing is badged on the tile', (
    tester,
  ) async {
    await pump(
      tester,
      MarkingTile(
        marking: Marking(
          id: 'm1',
          animal: 'a1',
          type: 'mktp_finder',
          code: 'AT-123',
          appliedAt: DateTime(2026, 3, 5),
          presentAtFind: true,
          isActive: true,
        ),
        caseId: 'c1',
      ),
    );

    expect(find.text('At find'), findsOneWidget);
  });

  testWidgets('shows when and deletes after confirming', (tester) async {
    when(() => markings.delete('m1')).thenAnswer((_) async {});

    await pump(
      tester,
      MarkingTile(
        marking: Marking(
          id: 'm1',
          animal: 'a1',
          type: 'mktp_finder',
          removedAt: DateTime(2026, 3, 4),
        ),
        caseId: 'c1',
      ),
    );

    expect(find.textContaining('Removed'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Delete marking?'), findsOneWidget);
    await tester.tap(find.widgetWithText(DestructiveActionButton, 'Delete'));
    await tester.pumpAndSettle();

    verify(() => markings.delete('m1')).called(1);
  });
}
