import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/admin/medication_products_screen.dart';
import 'package:federfall/features/cases/medications/cycle_preview.dart';
import 'package:federfall/features/cases/medications/medication_products_providers.dart';
import 'package:federfall/features/cases/medications/medication_routes_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/theme/app_theme.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart' hide Finder;
import 'package:mocktail/mocktail.dart';

class MockProductsRepo extends Mock implements PbMedicationProductsRepository {}

void main() {
  setUpAll(() => registerFallbackValue(<String, dynamic>{}));

  late MockProductsRepo products;

  setUp(() => products = MockProductsRepo());

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    List<MedicationProduct> catalogue = const [],
    UserRole role = UserRole.supervisor,
  }) async {
    final container = ProviderContainer(
      overrides: [
        currentUserProvider.overrideWith(
          (ref) async =>
              AppUser(id: 'u1', email: 'me@x.org', org: 'org1', role: role),
        ),
        medicationProductsRepositoryProvider.overrideWith(
          (ref) async => products,
        ),
        medicationProductsProvider.overrideWith((ref) async => catalogue),
        medicationRoutesProvider.overrideWith((ref) async => const []),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: child),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('MedicationProductsScreen', () {
    testWidgets('lists an entry with its dosing summary', (tester) async {
      await pump(
        tester,
        const MedicationProductsScreen(),
        catalogue: const [
          MedicationProduct(
            id: 'p1',
            label: 'Medikament 1',
            doseUnit: 'mg',
            doseRate: 20,
            concentrationPerMl: 15,
          ),
          MedicationProduct(id: 'p2', label: 'Retired', active: false),
        ],
      );

      expect(find.text('Medikament 1'), findsOneWidget);
      expect(find.text('20 mg/kg · 15 mg/ml'), findsOneWidget);
      // A deactivated entry stays listed for the supervisor, marked as such.
      expect(find.textContaining('Inactive'), findsOneWidget);
    });

    testWidgets('walls off a carer, since the rules do too', (tester) async {
      await pump(
        tester,
        const MedicationProductsScreen(),
        role: UserRole.carer,
      );

      expect(
        find.text('You are not authorized to do that'),
        findsOneWidget,
      );
      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('stores an entry with its advisory range', (tester) async {
      when(() => products.create(any())).thenAnswer(
        (_) async => const MedicationProduct(id: 'p9', label: 'x'),
      );

      await pump(tester, const MedicationProductSheet());

      await tester.enterText(
        find.widgetWithText(TextField, 'Drug'),
        'Medikament 4',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Dose per kg body weight'),
        '20',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Range from'),
        '10',
      );
      await tester.enterText(find.widgetWithText(TextField, 'to'), '30');
      await tester.enterText(
        find.widgetWithText(TextField, 'Product concentration'),
        '15',
      );
      await tester.pumpAndSettle();

      final save = find.widgetWithText(FilledButton, 'Save');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();

      final body =
          verify(() => products.create(captureAny())).captured.single
              as Map<String, dynamic>;
      expect(body['label'], 'Medikament 4');
      expect(body['dose_rate'], 20);
      expect(body['rate_min'], 10);
      expect(body['rate_max'], 30);
      expect(body['concentration_per_ml'], 15);
      expect(body['org'], 'org1');
    });
  });

  // The give/pause pair is validated AS a pair, and the switch is what makes
  // "no rhythm" a state somebody can see. Before federfall-sh9e the two day
  // fields were simply always there for a custom interval, a `0` in one of them
  // answered "Pflichtfeld", and a cycle count with no pair was dropped on save
  // without a word.
  group('MedicationProductSheet cycle', () {
    Future<void> chooseCustomInterval(WidgetTester tester) async {
      await tester.tap(
        find.byType(DropdownButtonFormField<MedicationFrequencyKind?>),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Custom interval').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Interval (hours)'),
        '12',
      );
      await tester.pumpAndSettle();
    }

    Future<void> turnOnCycle(WidgetTester tester) async {
      await tester.ensureVisible(find.text('Cyclic schedule'));
      await tester.tap(find.text('Cyclic schedule'));
      await tester.pumpAndSettle();
    }

    Future<void> save(WidgetTester tester) async {
      final button = find.widgetWithText(FilledButton, 'Save');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    Future<void> openNew(WidgetTester tester) async {
      when(() => products.create(any())).thenAnswer(
        (_) async => const MedicationProduct(id: 'p9', label: 'x'),
      );
      await pump(tester, const MedicationProductSheet());
      await tester.enterText(find.widgetWithText(TextField, 'Drug'), 'Baytril');
      await chooseCustomInterval(tester);
    }

    testWidgets('the day fields stay out of the way until the switch is on', (
      tester,
    ) async {
      await openNew(tester);
      expect(find.widgetWithText(TextField, 'Days on'), findsNothing);
      expect(find.widgetWithText(TextField, 'Cycles'), findsNothing);

      await save(tester);
      final body =
          verify(() => products.create(captureAny())).captured.single
              as Map<String, dynamic>;
      expect(body['interval_hours'], 12);
      expect(body['cycle_on_days'], isNull);
      expect(body['cycle_off_days'], isNull);
    });

    testWidgets('the switch on with both halves empty saves as no rhythm', (
      tester,
    ) async {
      await openNew(tester);
      await turnOnCycle(tester);

      // It says what the empty pair will do rather than blocking the save.
      expect(find.text('Left empty, no rhythm is saved.'), findsOneWidget);
      await save(tester);

      final body =
          verify(() => products.create(captureAny())).captured.single
              as Map<String, dynamic>;
      expect(body['cycle_on_days'], isNull);
      expect(body['cycle_off_days'], isNull);
    });

    testWidgets('zero is refused, and the message says where the exit is', (
      tester,
    ) async {
      await openNew(tester);
      await turnOnCycle(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Days on'), '5');
      await tester.enterText(find.widgetWithText(TextField, 'Days off'), '0');
      await tester.pumpAndSettle();
      await save(tester);

      expect(
        find.text(
          'At least 1 day — switch the rhythm off for a course with no pause.',
        ),
        findsOneWidget,
      );
      verifyNever(() => products.create(any()));
    });

    testWidgets('one half filled makes the other required', (tester) async {
      await openNew(tester);
      await turnOnCycle(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Days on'), '5');
      await tester.pumpAndSettle();
      await save(tester);

      expect(find.text('This field is required'), findsOneWidget);
      verifyNever(() => products.create(any()));
    });

    testWidgets('a cycle count with no rhythm is refused, not dropped', (
      tester,
    ) async {
      await openNew(tester);
      await turnOnCycle(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Cycles'), '3');
      await tester.pumpAndSettle();
      await save(tester);

      expect(
        find.text(
          'Cycles need a rhythm — please fill in days on and days off.',
        ),
        findsOneWidget,
      );
      verifyNever(() => products.create(any()));
    });

    testWidgets('a whole rhythm reaches the record', (tester) async {
      await openNew(tester);
      await turnOnCycle(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Days on'), '5');
      await tester.enterText(find.widgetWithText(TextField, 'Days off'), '2');
      await tester.enterText(find.widgetWithText(TextField, 'Cycles'), '3');
      await tester.pumpAndSettle();

      expect(find.byType(MedicationCyclePreview), findsOneWidget);
      await save(tester);

      final body =
          verify(() => products.create(captureAny())).captured.single
              as Map<String, dynamic>;
      expect(body['cycle_on_days'], 5);
      expect(body['cycle_off_days'], 2);
      expect(body['cycle_repeats'], 3);
    });

    testWidgets('editing an entry with a rhythm opens with the switch on', (
      tester,
    ) async {
      await pump(
        tester,
        const MedicationProductSheet(
          product: MedicationProduct(
            id: 'p1',
            label: 'Baytril',
            frequencyKind: MedicationFrequencyKind.scheduled,
            intervalHours: 12,
            cycleOnDays: 5,
            cycleOffDays: 2,
            cycleRepeats: 3,
          ),
        ),
      );

      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Days on'))
            .controller!
            .text,
        '5',
      );
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Cycles'))
            .controller!
            .text,
        '3',
      );
    });

    testWidgets('a stored zero pair leaves the switch off', (tester) async {
      // PocketBase has no null for a number field, so a hand-built record can
      // still carry the zeroes `pbCount` normally strips — two of which used to
      // read as "cyclic" and block every save (federfall-h9d5).
      await pump(
        tester,
        const MedicationProductSheet(
          product: MedicationProduct(
            id: 'p1',
            label: 'Baytril',
            frequencyKind: MedicationFrequencyKind.scheduled,
            intervalHours: 12,
            cycleOnDays: 0,
            cycleOffDays: 0,
          ),
        ),
      );

      expect(find.widgetWithText(TextField, 'Days on'), findsNothing);
    });
  });

  group('MedicationProduct', () {
    test('judges a rate against its range, or abstains without one', () {
      const bounded = MedicationProduct(
        id: 'p1',
        label: 'x',
        rateMin: 10,
        rateMax: 30,
      );
      expect(bounded.isOutOfRange(20), isFalse);
      expect(bounded.isOutOfRange(10), isFalse);
      expect(bounded.isOutOfRange(30), isFalse);
      expect(bounded.isOutOfRange(9.9), isTrue);
      expect(bounded.isOutOfRange(31), isTrue);

      // No range recorded — an unbounded entry cannot judge anything.
      const open = MedicationProduct(id: 'p2', label: 'x');
      expect(open.isOutOfRange(1000), isFalse);
      expect(open.range, isNull);

      const halfOpen = MedicationProduct(id: 'p3', label: 'x', rateMax: 30);
      expect(halfOpen.isOutOfRange(0.1), isFalse);
      expect(halfOpen.isOutOfRange(31), isTrue);
    });
  });
}
