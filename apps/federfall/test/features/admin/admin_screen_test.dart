import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/features/admin/admin_screen.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, AppUser user) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) async => user),
      ],
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AdminScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a supervisor sees the admin placeholder', (tester) async {
    await _pump(
      tester,
      const AppUser(id: 'u1', email: 's@x.org', role: UserRole.supervisor),
    );

    expect(
      find.text('Team management and invites are coming soon.'),
      findsOneWidget,
    );
  });

  testWidgets('a carer is shown an unauthorized message', (tester) async {
    await _pump(
      tester,
      const AppUser(id: 'u1', email: 'c@x.org', role: UserRole.carer),
    );

    expect(find.text('You are not authorized to do that'), findsOneWidget);
  });
}
