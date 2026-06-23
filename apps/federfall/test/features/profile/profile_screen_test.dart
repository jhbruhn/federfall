import 'dart:async';

import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/profile/profile_screen.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeAuthRepository implements AuthRepository {
  bool signedOut = false;

  @override
  Stream<AppUser?> get changes => const Stream.empty();

  @override
  AppUser? currentUser;

  @override
  bool isSignedIn = true;

  @override
  Future<AppUser> signIn(String email, String password) async =>
      throw UnimplementedError();

  @override
  Future<AppUser?> refresh() async => currentUser;

  @override
  void signOut() => signedOut = true;
}

Future<void> _pump(WidgetTester tester, FakeAuthRepository repo,
    AppUser user) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWith((ref) async => repo),
        currentUserProvider.overrideWith((ref) async => user),
      ],
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ProfileScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the user email and localized role', (tester) async {
    await _pump(
      tester,
      FakeAuthRepository(),
      const AppUser(id: 'u1', email: 'sup@x.org', role: UserRole.supervisor),
    );

    expect(find.text('sup@x.org'), findsOneWidget);
    expect(find.text('Supervisor'), findsOneWidget);
  });

  testWidgets('signs out from the profile action', (tester) async {
    final repo = FakeAuthRepository();
    await _pump(
      tester,
      repo,
      const AppUser(id: 'u1', email: 'c@x.org', role: UserRole.carer),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(repo.signedOut, isTrue);
  });
}
