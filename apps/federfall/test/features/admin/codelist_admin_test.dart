import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/admin/codelist_admin.dart';
import 'package:federfall/features/admin/codelist_specs.dart';
import 'package:federfall/features/cases/conditions/conditions_providers.dart';
import 'package:federfall/features/cases/markings/marking_types_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockConditionsRepo extends Mock implements PbConditionsRepository {}

class MockMarkingTypesRepo extends Mock implements PbMarkingTypesRepository {}

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

  testWidgets('deleting a condition confirms and calls the repo', (
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
      ],
    );

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete condition').last);
    await tester.pumpAndSettle();
    // Confirm in the dialog.
    await tester.tap(find.widgetWithText(TextButton, 'Delete condition').last);
    await tester.pumpAndSettle();

    verify(() => repo.delete('c1')).called(1);
  });
}
