import 'dart:async';

import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/admin/admin_screen.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeAuthRepository implements AuthRepository {
  String? invitedEmail;
  UserRole? invitedRole;

  @override
  Future<AppUser> inviteUser({
    required String email,
    required UserRole role,
    String? name,
  }) async {
    invitedEmail = email;
    invitedRole = role;
    return AppUser(id: 'new1', email: email, role: role);
  }

  @override
  Stream<AppUser?> get changes => const Stream.empty();
  @override
  AppUser? currentUser;
  @override
  bool isSignedIn = true;
  @override
  Future<AppUser> signIn(String e, String p) async =>
      throw UnimplementedError();
  @override
  Future<AppUser?> refresh() async => null;
  @override
  void signOut() {}
  @override
  Future<void> requestPasswordReset(String email) async {}
  @override
  Future<void> confirmPasswordReset(String token, String password) async {}
}

Future<void> _pump(
  WidgetTester tester, {
  required FakeAuthRepository repo,
  required UserRole role,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWith((ref) async => repo),
        currentUserProvider.overrideWith(
          (ref) async => AppUser(id: 'u1', email: 'me@x.org', role: role),
        ),
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
  testWidgets('a carer is shown an unauthorized message', (tester) async {
    await _pump(tester, repo: FakeAuthRepository(), role: UserRole.carer);
    expect(find.text('You are not authorized to do that'), findsOneWidget);
  });

  testWidgets('a supervisor sees the invite form', (tester) async {
    await _pump(tester, repo: FakeAuthRepository(), role: UserRole.supervisor);
    expect(find.text('Invite a member'), findsOneWidget);
  });

  testWidgets('sending an invite calls the repo and confirms', (tester) async {
    final repo = FakeAuthRepository();
    await _pump(tester, repo: repo, role: UserRole.supervisor);

    await tester.enterText(
      find.byType(TextFormField).first,
      'new@x.org',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Send invite'));
    await tester.pumpAndSettle();

    expect(repo.invitedEmail, 'new@x.org');
    expect(repo.invitedRole, UserRole.carer);
    expect(find.text('Invite sent to new@x.org.'), findsOneWidget);
  });
}
