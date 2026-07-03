import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/admin/org_settings_providers.dart';
import 'package:federfall/features/admin/org_settings_screen.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockOrgRepo extends Mock implements PbOrganisationsRepository {}

Future<void> _pump(
  WidgetTester tester, {
  required UserRole role,
  Organisation? org,
  PbOrganisationsRepository? repo,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWith(
          (ref) async =>
              AppUser(id: 'u1', email: 'me@x.org', role: role, org: 'org1'),
        ),
        if (org != null)
          currentOrganisationProvider.overrideWith((ref) async => org),
        if (repo != null)
          organisationsRepositoryProvider.overrideWith((ref) async => repo),
      ],
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: OrgSettingsScreen(),
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

  testWidgets('a supervisor sees the org form prefilled', (tester) async {
    await _pump(
      tester,
      role: UserRole.supervisor,
      org: const Organisation(id: 'org1', name: 'Pigeon Aid'),
    );
    expect(find.text('Pigeon Aid'), findsOneWidget);
    // Retention defaults to 24 months when unset.
    expect(find.text('24'), findsOneWidget);
  });

  testWidgets('saving persists merged settings and contact details', (
    tester,
  ) async {
    final repo = MockOrgRepo();
    when(() => repo.update(any(), any())).thenAnswer(
      (_) async => const Organisation(id: 'org1', name: 'Pigeon Aid'),
    );

    await _pump(
      tester,
      role: UserRole.supervisor,
      org: const Organisation(
        id: 'org1',
        name: 'Pigeon Aid',
        settings: {'keepMe': true},
      ),
      repo: repo,
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Contact email'),
      'help@x.org',
    );
    final save = find.widgetWithText(FilledButton, 'Save');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();

    final data =
        verify(() => repo.update('org1', captureAny())).captured.single
            as Map<String, dynamic>;
    expect(data['contact_email'], 'help@x.org');
    final settings = data['settings'] as Map<String, dynamic>;
    expect(settings['keepMe'], true); // pre-existing keys preserved
    expect(settings[finderRetentionMonthsKey], 24);
    expect(settings[quarantineDefaultDaysKey], 14);
  });

  testWidgets('a blanked or zero retention blocks the save with a message', (
    tester,
  ) async {
    final repo = MockOrgRepo();

    await _pump(
      tester,
      role: UserRole.supervisor,
      org: const Organisation(id: 'org1', name: 'Pigeon Aid'),
      repo: repo,
    );

    final retention = find.widgetWithText(
      TextFormField,
      'Finder data retention (months)',
    );
    final save = find.widgetWithText(FilledButton, 'Save');

    await tester.enterText(retention, '');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('This field is required'), findsOneWidget);

    await tester.enterText(retention, '0');
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('Enter a number of at least 1'), findsOneWidget);

    verifyNever(() => repo.update(any(), any()));
  });
}
