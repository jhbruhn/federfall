import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/features/admin/management_screen.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, {required UserRole role}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWith(
          (ref) async => AppUser(id: 'u1', email: 'me@x.org', role: role),
        ),
      ],
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ManagementScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a carer is shown an unauthorized message', (tester) async {
    await _pump(tester, role: UserRole.carer);
    expect(find.text('You are not authorized to do that'), findsOneWidget);
  });

  testWidgets('a supervisor sees every management entry', (tester) async {
    await _pump(tester, role: UserRole.supervisor);
    expect(find.text('Team'), findsOneWidget);
    expect(find.text('Organisation settings'), findsOneWidget);
    expect(find.text('Condition code-list'), findsOneWidget);
    expect(find.text('Statistics'), findsOneWidget);
  });
}
