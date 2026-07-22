import 'dart:async';

import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/auth/confirm_reset_screen.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class FakeAuthRepository implements AuthRepository {
  String? resetToken;
  String? resetPassword;

  @override
  Future<void> confirmPasswordReset(String token, String password) async {
    resetToken = token;
    resetPassword = password;
  }

  @override
  Stream<AppUser?> get changes => const Stream.empty();
  @override
  AppUser? currentUser;
  @override
  bool isSignedIn = false;
  @override
  Future<AppUser> signIn(String e, String p) async =>
      throw UnimplementedError();
  @override
  Future<AppUser?> refresh() async => null;
  @override
  void signOut() {}
  @override
  Future<AppUser> inviteUser({
    required String email,
    required UserRole role,
    String? name,
  }) async => throw UnimplementedError();
  @override
  Future<AppUser> updateProfile({String? name, String? phone}) async =>
      throw UnimplementedError();

  @override
  Future<void> requestPasswordReset(String email) async {}

  @override
  Future<String> requestOtp(String email) async => throw UnimplementedError();

  @override
  Future<AppUser> authWithOtp({
    required String otpId,
    required String code,
    required String mfaId,
  }) async => throw UnimplementedError();

  @override
  Future<AppUser> setMfaEnabled({required bool enabled}) async =>
      throw UnimplementedError();

  @override
  Future<List<OAuthProvider>> oauthProviders() async => const [];

  @override
  Future<AppUser> signInWithOAuth2(
    String provider,
    Future<void> Function(Uri url) openUrl,
  ) async => throw UnimplementedError();

  @override
  Future<AppUser> signInWithOAuth2Code(
    String provider, {
    required String redirectUrl,
    required Future<String> Function(Uri authorizationUrl) authenticate,
  }) async => throw UnimplementedError();
}

Future<void> _pump(
  WidgetTester tester, {
  required FakeAuthRepository repo,
  required String initialLocation,
}) async {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/login',
        builder: (_, _) => const Scaffold(body: Text('LOGIN')),
      ),
      GoRoute(
        path: '/auth/confirm-reset',
        builder: (_, state) =>
            ConfirmResetScreen(token: state.uri.queryParameters['token']),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWith((ref) async => repo),
      ],
      child: MaterialApp.router(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('sets the password and routes to login', (tester) async {
    final repo = FakeAuthRepository();
    await _pump(
      tester,
      repo: repo,
      initialLocation: '/auth/confirm-reset?token=tok123',
    );

    await tester.enterText(find.byType(TextFormField).first, 'newpass123');
    await tester.enterText(find.byType(TextFormField).last, 'newpass123');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(repo.resetToken, 'tok123');
    expect(repo.resetPassword, 'newpass123');
    expect(find.text('LOGIN'), findsOneWidget);
  });

  testWidgets('shows an error when the passwords differ', (tester) async {
    await _pump(
      tester,
      repo: FakeAuthRepository(),
      initialLocation: '/auth/confirm-reset?token=tok123',
    );

    await tester.enterText(find.byType(TextFormField).first, 'newpass123');
    await tester.enterText(find.byType(TextFormField).last, 'different');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Passwords do not match.'), findsOneWidget);
  });

  testWidgets('rejects a password under 8 characters', (tester) async {
    final repo = FakeAuthRepository();
    await _pump(
      tester,
      repo: repo,
      initialLocation: '/auth/confirm-reset?token=tok123',
    );

    await tester.enterText(find.byType(TextFormField).first, 'short12');
    await tester.enterText(find.byType(TextFormField).last, 'short12');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Must be at least 8 characters'), findsOneWidget);
    expect(repo.resetToken, isNull);
  });

  testWidgets('rejects a missing token', (tester) async {
    final repo = FakeAuthRepository();
    await _pump(
      tester,
      repo: repo,
      initialLocation: '/auth/confirm-reset',
    );

    await tester.enterText(find.byType(TextFormField).first, 'newpass123');
    await tester.enterText(find.byType(TextFormField).last, 'newpass123');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('This link is invalid or has expired.'), findsOneWidget);
    expect(repo.resetToken, isNull);
  });
}
