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
    // Statistics is reached from the account menu / rail, not the hub.
    expect(find.text('Statistics'), findsNothing);
  });

  testWidgets('wide screens show the hub beside a selection placeholder', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pump(tester, role: UserRole.supervisor);

    // Hub on the left, empty-selection placeholder on the right, and the
    // persistent app bar (which carries the back-to-app affordance) on top —
    // the hub stays a single screen, so that affordance never disappears.
    expect(find.text('Team'), findsOneWidget);
    expect(find.text('Select a section to manage'), findsOneWidget);
    expect(find.text('Administration'), findsOneWidget);
  });
}
