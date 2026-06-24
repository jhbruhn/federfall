import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/features/cases/placements/placements_providers.dart';
import 'package:federfall/features/cases/sharing/case_share_sheet.dart';
import 'package:federfall/features/cases/sharing/sharing_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _me = AppUser(id: 'u1', email: 'me@x.org', role: UserRole.carer);
const _bob = AppUser(id: 'u2', email: 'b@x.org', name: 'Bob');
const _cara = AppUser(id: 'u3', email: 'c@x.org', name: 'Cara');

Future<void> _open(
  WidgetTester tester, {
  required List<CaseShare> shares,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) async => _me),
        orgMembersProvider.overrideWith((ref) async => [_me, _bob, _cara]),
        caseSharesProvider('c1').overrideWith((ref) async => shares),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () =>
                  showCaseShareSheet(context, caseId: 'c1', activeCarer: 'u1'),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists current shares with member name, access and revoke',
      (tester) async {
    await _open(
      tester,
      shares: const [
        CaseShare(
          id: 's1',
          caseId: 'c1',
          sharedWith: 'u2',
          access: ShareAccess.edit,
        ),
      ],
    );

    expect(find.text('Share case'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Edit'), findsWidgets);
    expect(find.byTooltip('Revoke access'), findsOneWidget);
  });

  testWidgets('shows the empty state and offers an eligible member',
      (tester) async {
    await _open(tester, shares: const []);

    expect(find.text('Not shared with anyone yet'), findsOneWidget);
    // Self (u1) and the active carer (u1) are excluded; Bob & Cara remain, so
    // the picker is offered rather than the no-members hint.
    expect(find.text('No other members to share with'), findsNothing);
    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
  });
}
