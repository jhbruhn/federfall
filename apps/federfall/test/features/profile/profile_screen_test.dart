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

  @override
  Future<AppUser> inviteUser({
    required String email,
    required UserRole role,
    String? name,
  }) async => throw UnimplementedError();

  String? updatedName;
  String? updatedPhone;

  @override
  Future<AppUser> updateProfile({String? name, String? phone}) async {
    updatedName = name;
    updatedPhone = phone;
    final u = currentUser!;
    return AppUser(id: u.id, email: u.email, name: name, phone: phone);
  }

  @override
  Future<void> requestPasswordReset(String email) async {}

  @override
  Future<void> confirmPasswordReset(String token, String password) async {}

  @override
  Future<String> requestOtp(String email) async => throw UnimplementedError();

  @override
  Future<AppUser> authWithOtp({
    required String otpId,
    required String code,
    required String mfaId,
  }) async => throw UnimplementedError();

  bool? mfaEnabledSetTo;

  @override
  Future<AppUser> setMfaEnabled({required bool enabled}) async {
    mfaEnabledSetTo = enabled;
    final u = currentUser!;
    return AppUser(id: u.id, email: u.email, mfaEnabled: enabled);
  }

  @override
  Future<List<OAuthProvider>> oauthProviders() async => const [];

  @override
  Future<AppUser> signInWithOAuth2(
    String provider,
    Future<void> Function(Uri url) openUrl,
  ) async => throw UnimplementedError();
}

Future<void> _pump(
  WidgetTester tester,
  FakeAuthRepository repo,
  AppUser user,
) async {
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

  testWidgets('editing the profile saves name and phone', (tester) async {
    final repo = FakeAuthRepository()
      ..currentUser = const AppUser(id: 'u1', email: 'c@x.org');
    await _pump(
      tester,
      repo,
      const AppUser(id: 'u1', email: 'c@x.org', role: UserRole.carer),
    );

    await tester.tap(find.byTooltip('Edit profile'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name'),
      'Jamie',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Phone'),
      '0123',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(repo.updatedName, 'Jamie');
    expect(repo.updatedPhone, '0123');
  });

  testWidgets('signs out from the profile action after confirming', (
    tester,
  ) async {
    final repo = FakeAuthRepository();
    await _pump(
      tester,
      repo,
      const AppUser(id: 'u1', email: 'c@x.org', role: UserRole.carer),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await tester.pumpAndSettle();

    // One accidental tap must not end the session — a confirm dialog
    // intervenes (federfall-u8l).
    expect(repo.signedOut, isFalse);
    expect(find.text('Sign out of this device?'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Sign out'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(repo.signedOut, isTrue);
  });

  testWidgets('cancelling the sign-out confirmation keeps the session', (
    tester,
  ) async {
    final repo = FakeAuthRepository();
    await _pump(
      tester,
      repo,
      const AppUser(id: 'u1', email: 'c@x.org', role: UserRole.carer),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(repo.signedOut, isFalse);
  });
}
