import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/admin/codelist_admin.dart';
import 'package:federfall/features/admin/codelist_specs.dart';
import 'package:federfall/features/cases/admission_reasons_providers.dart';
import 'package:federfall/features/cases/conditions/conditions_providers.dart';
import 'package:federfall/features/cases/markings/marking_types_providers.dart';
import 'package:federfall/features/cases/medications/medication_routes_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockConditionsRepo extends Mock implements PbConditionsRepository {}

class MockMarkingTypesRepo extends Mock implements PbMarkingTypesRepository {}

class MockCaseConditionsRepo extends Mock
    implements PbCaseConditionsRepository {}

class MockMarkingsRepo extends Mock implements PbMarkingsRepository {}

class MockAdmissionReasonsRepo extends Mock
    implements PbAdmissionReasonsRepository {}

class MockCasesRepo extends Mock implements PbCasesRepository {}

class MockMedicationRoutesRepo extends Mock
    implements PbMedicationRoutesRepository {}

class MockMedicationsRepo extends Mock implements PbMedicationsRepository {}

class MockAdministrationsRepo extends Mock
    implements PbMedicationAdministrationsRepository {}

class MockMedicationProductsRepo extends Mock
    implements PbMedicationProductsRepository {}

/// Overrides the collection that references the conditions code list, so the
/// delete confirmation can count how many diagnoses point at an entry.
List<Override> _conditionRefs(int count) {
  final refs = MockCaseConditionsRepo();
  when(() => refs.countForCondition(any())).thenAnswer((_) async => count);
  return [caseConditionsRepositoryProvider.overrideWith((ref) async => refs)];
}

/// Same for the marking types list, whose referencing relation is required.
List<Override> _markingRefs(int count) {
  final refs = MockMarkingsRepo();
  when(() => refs.countForType(any())).thenAnswer((_) async => count);
  return [markingsRepositoryProvider.overrideWith((ref) async => refs)];
}

/// Taps the row's delete button.
Future<void> _tapDelete(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.delete_outline));
  await tester.pumpAndSettle();
}

Future<void> _pump(
  WidgetTester tester, {
  required UserRole role,
  required Widget screen,
  List<Override> overrides = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWith(
          (ref) async =>
              AppUser(id: 'u1', email: 'me@x.org', role: role, org: 'org1'),
        ),
        ...overrides,
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: screen,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => registerFallbackValue(<String, dynamic>{}));

  testWidgets('a carer is shown an unauthorized message', (tester) async {
    await _pump(
      tester,
      role: UserRole.carer,
      screen: CodelistAdminScreen(spec: conditionsCodelistSpec),
    );
    expect(find.text('You are not authorized to do that'), findsOneWidget);
  });

  testWidgets(
    'lists conditions with notifiable, contagious and inactive badges',
    (tester) async {
      await _pump(
        tester,
        role: UserRole.supervisor,
        screen: CodelistAdminScreen(spec: conditionsCodelistSpec),
        overrides: [
          conditionsProvider.overrideWith(
            (ref) async => const [
              Condition(id: 'c1', label: 'Trichomoniasis', isNotifiable: true),
              Condition(id: 'c2', label: 'Old entry', active: false),
              Condition(id: 'c3', label: 'Kokzidiose', isContagious: true),
            ],
          ),
        ],
      );
      expect(find.text('Trichomoniasis'), findsOneWidget);
      expect(find.text('Old entry'), findsOneWidget);
      expect(find.text('Kokzidiose'), findsOneWidget);
      expect(find.textContaining('Notifiable'), findsOneWidget);
      expect(find.textContaining('Contagious'), findsOneWidget);
      expect(find.textContaining('Inactive'), findsOneWidget);
    },
  );

  testWidgets('adding a condition creates it scoped to the org, including '
      'the condition-only fields', (tester) async {
    final repo = MockConditionsRepo();
    when(() => repo.create(any())).thenAnswer(
      (_) async => const Condition(id: 'new', label: 'Paramyxovirus'),
    );

    await _pump(
      tester,
      role: UserRole.supervisor,
      screen: CodelistAdminScreen(spec: conditionsCodelistSpec),
      overrides: [
        conditionsProvider.overrideWith((ref) async => const []),
        conditionsRepositoryProvider.overrideWith((ref) async => repo),
      ],
    );

    await tester.tap(
      find.widgetWithText(FloatingActionButton, 'New condition'),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name'),
      'Paramyxovirus',
    );
    final saveButton = find.widgetWithText(FilledButton, 'Save');
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    final data =
        verify(() => repo.create(captureAny())).captured.single
            as Map<String, dynamic>;
    expect(data['label'], 'Paramyxovirus');
    expect(data['org'], 'org1');
    expect(data['active'], true);
    // The conditions spec carries the three extra fields.
    expect(data['description'], '');
    expect(data['is_notifiable'], false);
    expect(data['is_contagious'], false);
  });

  testWidgets('a label-only list omits the condition-only fields on create', (
    tester,
  ) async {
    final repo = MockMarkingTypesRepo();
    when(() => repo.create(any())).thenAnswer(
      (_) async => const MarkingType(id: 'new', label: 'Ring'),
    );

    await _pump(
      tester,
      role: UserRole.supervisor,
      screen: CodelistAdminScreen(spec: markingTypesCodelistSpec),
      overrides: [
        markingTypesProvider.overrideWith((ref) async => const []),
        markingTypesRepositoryProvider.overrideWith((ref) async => repo),
      ],
    );

    await tester.tap(
      find.widgetWithText(FloatingActionButton, 'New marking type'),
    );
    await tester.pumpAndSettle();

    // A {label, active} list gets no description field or notifiable switch.
    expect(find.byType(SwitchListTile), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Ring');
    final saveButton = find.widgetWithText(FilledButton, 'Save');
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    final data =
        verify(() => repo.create(captureAny())).captured.single
            as Map<String, dynamic>;
    expect(data['label'], 'Ring');
    expect(data['org'], 'org1');
    expect(data['active'], true);
    expect(data.containsKey('description'), isFalse);
    expect(data.containsKey('is_notifiable'), isFalse);
    expect(data.containsKey('is_contagious'), isFalse);
  });

  testWidgets('editing a condition can flip the contagious switch', (
    tester,
  ) async {
    final repo = MockConditionsRepo();
    when(() => repo.update(any(), any())).thenAnswer(
      (_) async =>
          const Condition(id: 'c1', label: 'Kokzidiose', isContagious: true),
    );

    await _pump(
      tester,
      role: UserRole.supervisor,
      screen: CodelistAdminScreen(spec: conditionsCodelistSpec),
      overrides: [
        conditionsProvider.overrideWith(
          (ref) async => const [Condition(id: 'c1', label: 'Kokzidiose')],
        ),
        conditionsRepositoryProvider.overrideWith((ref) async => repo),
      ],
    );

    await tester.tap(find.text('Kokzidiose'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(SwitchListTile, 'Contagious'));
    final saveButton = find.widgetWithText(FilledButton, 'Save');
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    final data =
        verify(() => repo.update('c1', captureAny())).captured.single
            as Map<String, dynamic>;
    expect(data['is_contagious'], true);
    expect(data['is_notifiable'], false);
  });

  testWidgets('deleting an UNREFERENCED condition confirms and calls the '
      'repo', (tester) async {
    final repo = MockConditionsRepo();
    when(() => repo.delete(any())).thenAnswer((_) async {});

    await _pump(
      tester,
      role: UserRole.supervisor,
      screen: CodelistAdminScreen(spec: conditionsCodelistSpec),
      overrides: [
        conditionsProvider.overrideWith(
          (ref) async => const [Condition(id: 'c1', label: 'Trichomoniasis')],
        ),
        conditionsRepositoryProvider.overrideWith((ref) async => repo),
        ..._conditionRefs(0),
      ],
    );

    await _tapDelete(tester);
    // Nothing points at it, so there is no count and no push to deactivate.
    expect(find.textContaining('is still in use'), findsNothing);
    expect(find.text('Deactivate instead'), findsNothing);

    await tester.tap(
      find.widgetWithText(DestructiveActionButton, 'Delete condition').last,
    );
    await tester.pumpAndSettle();

    verify(() => repo.delete('c1')).called(1);
  });

  testWidgets('a REFERENCED condition names the count, states what a delete '
      'would do, and makes deactivating the primary action', (tester) async {
    final repo = MockConditionsRepo();
    when(() => repo.update(any(), any())).thenAnswer(
      (_) async => const Condition(id: 'c1', label: 'Trichomoniasis'),
    );

    await _pump(
      tester,
      role: UserRole.supervisor,
      screen: CodelistAdminScreen(spec: conditionsCodelistSpec),
      overrides: [
        conditionsProvider.overrideWith(
          (ref) async => const [Condition(id: 'c1', label: 'Trichomoniasis')],
        ),
        conditionsRepositoryProvider.overrideWith((ref) async => repo),
        ..._conditionRefs(3),
      ],
    );

    await _tapDelete(tester);

    expect(find.textContaining('"Trichomoniasis" is still in use'), findsOne);
    expect(
      find.textContaining('3 recorded diagnoses use this condition'),
      findsOne,
    );
    // The consequence PocketBase actually applies: the field is blanked.
    expect(find.textContaining('what was recorded there is gone'), findsOne);
    // Deactivating is the filled (primary) button; the delete is demoted to a
    // plain text button, so the two are not distinguished by colour alone.
    expect(
      find.widgetWithText(FilledButton, 'Deactivate instead'),
      findsOne,
    );
    expect(
      find.widgetWithText(DestructiveActionButton, 'Delete anyway'),
      findsOne,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Deactivate instead'));
    await tester.pumpAndSettle();

    // Deactivated, NOT deleted — the diagnoses keep reading.
    final body =
        verify(() => repo.update('c1', captureAny())).captured.single
            as Map<String, dynamic>;
    expect(body['active'], false);
    verifyNever(() => repo.delete(any()));
  });

  testWidgets('"Delete anyway" on a referenced entry still deletes it', (
    tester,
  ) async {
    final repo = MockConditionsRepo();
    when(() => repo.delete(any())).thenAnswer((_) async {});

    await _pump(
      tester,
      role: UserRole.supervisor,
      screen: CodelistAdminScreen(spec: conditionsCodelistSpec),
      overrides: [
        conditionsProvider.overrideWith(
          (ref) async => const [Condition(id: 'c1', label: 'Trichomoniasis')],
        ),
        conditionsRepositoryProvider.overrideWith((ref) async => repo),
        ..._conditionRefs(3),
      ],
    );

    await _tapDelete(tester);
    await tester.tap(
      find.widgetWithText(DestructiveActionButton, 'Delete anyway'),
    );
    await tester.pumpAndSettle();

    verify(() => repo.delete('c1')).called(1);
  });

  testWidgets('a referenced MARKING TYPE offers no delete at all — the '
      'required relation means the server would refuse it', (tester) async {
    final repo = MockMarkingTypesRepo();
    when(() => repo.update(any(), any())).thenAnswer(
      (_) async => const MarkingType(id: 't1', label: 'Ring'),
    );

    await _pump(
      tester,
      role: UserRole.supervisor,
      screen: CodelistAdminScreen(spec: markingTypesCodelistSpec),
      overrides: [
        markingTypesProvider.overrideWith(
          (ref) async => const [MarkingType(id: 't1', label: 'Ring')],
        ),
        markingTypesRepositoryProvider.overrideWith((ref) async => repo),
        ..._markingRefs(1),
      ],
    );

    await _tapDelete(tester);

    expect(find.textContaining('1 marking uses this type'), findsOne);
    expect(find.textContaining('cannot be deleted while they exist'), findsOne);
    expect(find.text('Delete anyway'), findsNothing);
    // No irreversible warning either: nothing irreversible is on offer.
    expect(find.text('This cannot be undone.'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Deactivate instead'), findsOne);
  });

  testWidgets('an already-inactive referenced entry is not offered '
      'deactivation again', (tester) async {
    await _pump(
      tester,
      role: UserRole.supervisor,
      screen: CodelistAdminScreen(spec: markingTypesCodelistSpec),
      overrides: [
        markingTypesProvider.overrideWith(
          (ref) async => const [
            MarkingType(id: 't1', label: 'Ring', active: false),
          ],
        ),
        markingTypesRepositoryProvider.overrideWith(
          (ref) async => MockMarkingTypesRepo(),
        ),
        ..._markingRefs(2),
      ],
    );

    await _tapDelete(tester);

    expect(find.textContaining('2 markings use this type'), findsOne);
    expect(find.text('Deactivate instead'), findsNothing);
    expect(find.text('Delete anyway'), findsNothing);
    // Purely informational — backing out is the only move.
    expect(find.widgetWithText(TextButton, 'Cancel'), findsOne);
  });

  testWidgets('an admission reason counts the cases that list it', (
    tester,
  ) async {
    final cases = MockCasesRepo();
    when(
      () => cases.countForAdmissionReason(any()),
    ).thenAnswer((_) async => 4);

    await _pump(
      tester,
      role: UserRole.supervisor,
      screen: CodelistAdminScreen(spec: admissionReasonsCodelistSpec),
      overrides: [
        admissionReasonsProvider.overrideWith(
          (ref) async => const [AdmissionReason(id: 'r1', label: 'Collision')],
        ),
        admissionReasonsRepositoryProvider.overrideWith(
          (ref) async => MockAdmissionReasonsRepo(),
        ),
        casesRepositoryProvider.overrideWith((ref) async => cases),
      ],
    );

    await _tapDelete(tester);

    expect(
      find.textContaining('4 cases list this admission reason'),
      findsOne,
    );
    verify(() => cases.countForAdmissionReason('r1')).called(1);
  });

  testWidgets('a route sums its three referring collections into one count', (
    tester,
  ) async {
    final prescriptions = MockMedicationsRepo();
    final doses = MockAdministrationsRepo();
    final products = MockMedicationProductsRepo();
    when(() => prescriptions.countForRoute(any())).thenAnswer((_) async => 2);
    when(() => doses.countForRoute(any())).thenAnswer((_) async => 3);
    when(() => products.countForRoute(any())).thenAnswer((_) async => 1);

    await _pump(
      tester,
      role: UserRole.supervisor,
      screen: CodelistAdminScreen(spec: medicationRoutesCodelistSpec),
      overrides: [
        medicationRoutesProvider.overrideWith(
          (ref) async => const [MedicationRoute(id: 'r1', label: 'Oral')],
        ),
        medicationRoutesRepositoryProvider.overrideWith(
          (ref) async => MockMedicationRoutesRepo(),
        ),
        medicationsRepositoryProvider.overrideWith(
          (ref) async => prescriptions,
        ),
        medicationAdministrationsRepositoryProvider.overrideWith(
          (ref) async => doses,
        ),
        medicationProductsRepositoryProvider.overrideWith(
          (ref) async => products,
        ),
      ],
    );

    await _tapDelete(tester);

    // 2 prescriptions + 3 logged doses + 1 catalogue entry.
    expect(
      find.textContaining(
        '6 prescriptions, logged doses and catalogue entries use this route',
      ),
      findsOne,
    );
  });

  testWidgets('a failed reference count aborts before anything is offered', (
    tester,
  ) async {
    final repo = MockConditionsRepo();
    final refs = MockCaseConditionsRepo();
    when(() => refs.countForCondition(any())).thenThrow(
      const RepositoryException('boom', kind: RepositoryErrorKind.network),
    );

    await _pump(
      tester,
      role: UserRole.supervisor,
      screen: CodelistAdminScreen(spec: conditionsCodelistSpec),
      overrides: [
        conditionsProvider.overrideWith(
          (ref) async => const [Condition(id: 'c1', label: 'Trichomoniasis')],
        ),
        conditionsRepositoryProvider.overrideWith((ref) async => repo),
        caseConditionsRepositoryProvider.overrideWith((ref) async => refs),
      ],
    );

    await _tapDelete(tester);

    // A count that could not be read must NOT degrade to "0 references" and a
    // bare "delete?" — no dialog is shown and nothing is deleted.
    expect(find.text('Delete anyway'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Cancel'), findsNothing);
    expect(find.byType(SnackBar), findsOne);
    verifyNever(() => repo.delete(any()));
  });
}
