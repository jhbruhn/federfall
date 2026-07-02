import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/admin/conditions_admin_screen.dart';
import 'package:federfall/features/cases/conditions/conditions_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockConditionsRepo extends Mock implements PbConditionsRepository {}

Future<void> _pump(
  WidgetTester tester, {
  required UserRole role,
  List<Condition> conditions = const [],
  PbConditionsRepository? repo,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWith(
          (ref) async =>
              AppUser(id: 'u1', email: 'me@x.org', role: role, org: 'org1'),
        ),
        conditionsProvider.overrideWith((ref) async => conditions),
        if (repo != null)
          conditionsRepositoryProvider.overrideWith((ref) async => repo),
      ],
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ConditionsAdminScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => registerFallbackValue(<String, dynamic>{}));

  testWidgets('a carer is shown an unauthorized message', (tester) async {
    await _pump(tester, role: UserRole.carer);
    expect(find.text('You are not authorized to do that'), findsOneWidget);
  });

  testWidgets('lists conditions with notifiable and inactive badges',
      (tester) async {
    await _pump(
      tester,
      role: UserRole.supervisor,
      conditions: const [
        Condition(id: 'c1', label: 'Trichomoniasis', isNotifiable: true),
        Condition(id: 'c2', label: 'Old entry', active: false),
      ],
    );
    expect(find.text('Trichomoniasis'), findsOneWidget);
    expect(find.text('Old entry'), findsOneWidget);
    expect(find.textContaining('Notifiable'), findsOneWidget);
    expect(find.textContaining('Inactive'), findsOneWidget);
  });

  testWidgets('adding a condition creates it scoped to the org',
      (tester) async {
    final repo = MockConditionsRepo();
    when(() => repo.create(any())).thenAnswer(
      (_) async => const Condition(id: 'new', label: 'Paramyxovirus'),
    );

    await _pump(tester, role: UserRole.supervisor, repo: repo);

    await tester.tap(
      find.widgetWithText(FloatingActionButton, 'New condition'),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name'),
      'Paramyxovirus',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final data =
        verify(() => repo.create(captureAny())).captured.single
            as Map<String, dynamic>;
    expect(data['label'], 'Paramyxovirus');
    expect(data['org'], 'org1');
    expect(data['active'], true);
  });

  testWidgets('deleting a condition confirms and calls the repo',
      (tester) async {
    final repo = MockConditionsRepo();
    when(() => repo.delete(any())).thenAnswer((_) async {});

    await _pump(
      tester,
      role: UserRole.supervisor,
      repo: repo,
      conditions: const [Condition(id: 'c1', label: 'Trichomoniasis')],
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
