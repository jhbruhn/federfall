import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/animals/delete_record_dialogs.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/features/cases/eggs/eggs_providers.dart';
import 'package:federfall/features/cases/exams/exams_providers.dart';
import 'package:federfall/features/cases/markings/markings_providers.dart';
import 'package:federfall/features/cases/weights/weights_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAnimalsRepo extends Mock implements PbAnimalsRepository {}

class MockCasesRepo extends Mock implements PbCasesRepository {}

const _animal = Animal(id: 'a1', species: 'Stadttaube', name: 'Paula');

void main() {
  late MockAnimalsRepo animals;
  late MockCasesRepo cases;

  setUp(() {
    animals = MockAnimalsRepo();
    cases = MockCasesRepo();
  });

  /// Pumps a button that opens the delete confirmation, and reports what the
  /// flow resolved to — the value the screens use to decide whether to navigate
  /// away from a record that no longer exists.
  Future<List<bool>> pumpDelete(
    WidgetTester tester, {
    required Future<bool> Function(BuildContext, WidgetRef) open,
    List<Case> animalCases = const [],
    List<Weight> weights = const [],
    List<EggRecord> eggs = const [],
    List<Marking> markings = const [],
    List<Exam> exams = const [],
    CaseBundle? bundle,
  }) async {
    final resolved = <bool>[];
    final container = ProviderContainer(
      overrides: [
        animalsRepositoryProvider.overrideWith((ref) async => animals),
        casesRepositoryProvider.overrideWith((ref) async => cases),
        casesForAnimalProvider('a1').overrideWith((ref) async => animalCases),
        weightsForAnimalProvider('a1').overrideWith((ref) async => weights),
        eggsForAnimalProvider('a1').overrideWith((ref) async => eggs),
        markingsForAnimalProvider('a1').overrideWith((ref) async => markings),
        examsForAnimalProvider('a1').overrideWith((ref) async => exams),
        if (bundle != null)
          caseBundleProvider('c1').overrideWith((ref) async => bundle),
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
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () async => resolved.add(await open(context, ref)),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    // Let the overridden providers settle so the dialog reads real counts
    // rather than the nulls of a still-loading future.
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return resolved;
  }

  group('confirmDeleteAnimal', () {
    testWidgets('enumerates what will be destroyed', (tester) async {
      await pumpDelete(
        tester,
        open: (context, ref) => confirmDeleteAnimal(context, ref, _animal),
        animalCases: const [
          Case(id: 'c1', animal: 'a1', status: CaseStatus.disposed),
          Case(id: 'c2', animal: 'a1', status: CaseStatus.inCare),
        ],
        weights: const [Weight(id: 'w1', animal: 'a1', weightG: 300)],
        // Counts sum `count`, so one row can be two eggs.
        eggs: const [EggRecord(id: 'e1', animal: 'a1', count: 2)],
        markings: const [Marking(id: 'm1', animal: 'a1', type: 't1')],
        exams: const [Exam(id: 'x1', caseId: 'c1', animal: 'a1')],
      );

      expect(
        find.text(
          'Paula · Stadttaube and everything recorded for it will be '
          'permanently deleted:',
        ),
        findsOneWidget,
      );
      expect(find.text('• 2 cases'), findsOneWidget);
      expect(
        find.text('• 1 weights · 2 eggs · 1 markings · 1 exams'),
        findsOneWidget,
      );
      expect(find.text('• This cannot be undone.'), findsNothing);
      expect(find.text('This cannot be undone.'), findsOneWidget);
    });

    testWidgets('names an open case instead of refusing the delete', (
      tester,
    ) async {
      await pumpDelete(
        tester,
        open: (context, ref) => confirmDeleteAnimal(context, ref, _animal),
        animalCases: const [
          Case(id: 'c1', animal: 'a1', status: CaseStatus.inCare),
          Case(id: 'c2', animal: 'a1', status: CaseStatus.disposed),
        ],
      );

      expect(find.text('• 1 of them is STILL IN CARE'), findsOneWidget);
      // The confirm button is live — an open case warns, it does not block.
      final confirm = tester.widget<DestructiveActionButton>(
        find.widgetWithText(DestructiveActionButton, 'Delete animal'),
      );
      expect(confirm.onPressed, isNotNull);
    });

    testWidgets('cancelling deletes nothing and resolves false', (
      tester,
    ) async {
      final resolved = await pumpDelete(
        tester,
        open: (context, ref) => confirmDeleteAnimal(context, ref, _animal),
      );

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      verifyNever(() => animals.delete(any()));
      expect(resolved, [false]);
    });

    testWidgets('confirming deletes the animal and resolves true', (
      tester,
    ) async {
      when(() => animals.delete('a1')).thenAnswer((_) async {});

      final resolved = await pumpDelete(
        tester,
        open: (context, ref) => confirmDeleteAnimal(context, ref, _animal),
      );

      await tester.tap(
        find.widgetWithText(DestructiveActionButton, 'Delete animal'),
      );
      await tester.pumpAndSettle();

      verify(() => animals.delete('a1')).called(1);
      expect(resolved, [true]);
    });

    testWidgets('a failed delete resolves false, so the screen stays put', (
      tester,
    ) async {
      when(() => animals.delete('a1')).thenThrow(Exception('nope'));

      final resolved = await pumpDelete(
        tester,
        open: (context, ref) => confirmDeleteAnimal(context, ref, _animal),
      );

      await tester.tap(
        find.widgetWithText(DestructiveActionButton, 'Delete animal'),
      );
      await tester.pumpAndSettle();

      expect(resolved, [false]);
    });
  });

  group('confirmDeleteCase', () {
    const medicalCase = Case(id: 'c1', animal: 'a1', caseNumber: '2026-014');

    testWidgets('counts the timeline and says the animal is kept', (
      tester,
    ) async {
      await pumpDelete(
        tester,
        open: (context, ref) => confirmDeleteCase(context, ref, medicalCase),
        bundle: const CaseBundle(
          medicalCase: medicalCase,
          journal: [JournalEntry(id: 'j1', caseId: 'c1', text: 'x')],
          medications: [Medication(id: 'm1', caseId: 'c1', drug: 'Baytril')],
          exams: [Exam(id: 'x1', caseId: 'c1', animal: 'a1')],
        ),
      );

      expect(
        find.text(
          'Case 2026-014 and its whole timeline will be permanently deleted:',
        ),
        findsOneWidget,
      );
      expect(
        find.text('• 1 journal entries · 1 medications · 0 doses · 1 exams'),
        findsOneWidget,
      );
      // Weights / eggs / markings are animal-level and do not cascade from a
      // case, so the dialog has to say so — otherwise "delete case" reads as
      // "delete everything".
      expect(
        find.text(
          '• The animal itself is kept, along with its weights, eggs and '
          'markings.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('confirming deletes the case', (tester) async {
      when(() => cases.delete('c1')).thenAnswer((_) async {});

      final resolved = await pumpDelete(
        tester,
        open: (context, ref) => confirmDeleteCase(context, ref, medicalCase),
        bundle: const CaseBundle(medicalCase: medicalCase),
      );

      await tester.tap(
        find.widgetWithText(DestructiveActionButton, 'Delete case'),
      );
      await tester.pumpAndSettle();

      verify(() => cases.delete('c1')).called(1);
      expect(resolved, [true]);
    });
  });
}
