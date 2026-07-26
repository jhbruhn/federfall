import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/admin/medication_products_screen.dart';
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
