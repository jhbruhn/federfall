import 'dart:async';

import 'package:federfall/core/server/server_config.dart';
import 'package:federfall/core/server/server_config_controller.dart';
import 'package:federfall/core/server/server_info.dart';
import 'package:federfall/core/server/server_info_provider.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/auth/login_screen.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.onSignIn, this.onRequestOtp, this.onAuthWithOtp});

  final Future<AppUser> Function(String email, String password)? onSignIn;
  final Future<String> Function(String email)? onRequestOtp;
  final Future<AppUser> Function(String otpId, String code, String mfaId)?
      onAuthWithOtp;

  String? lastEmail;
  String? lastPassword;
  String? lastOtpCode;
  final _changes = StreamController<AppUser?>.broadcast();

  @override
  Stream<AppUser?> get changes => _changes.stream;

  @override
  AppUser? currentUser;

  @override
  bool isSignedIn = false;

  @override
  Future<AppUser> signIn(String email, String password) async {
    lastEmail = email;
    lastPassword = password;
    if (onSignIn != null) return onSignIn!(email, password);
    return const AppUser(id: 'u1', email: 'staff@example.org');
  }

  @override
  Future<AppUser?> refresh() async => currentUser;

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
  Future<void> confirmPasswordReset(String token, String password) async {}

  @override
  Future<String> requestOtp(String email) async =>
      onRequestOtp != null ? onRequestOtp!(email) : 'otp1';

  @override
  Future<AppUser> authWithOtp({
    required String otpId,
    required String code,
    required String mfaId,
  }) async {
    lastOtpCode = code;
    if (onAuthWithOtp != null) return onAuthWithOtp!(otpId, code, mfaId);
    return const AppUser(id: 'u1', email: 'staff@example.org');
  }

  @override
  Future<AppUser> setMfaEnabled({required bool enabled}) async =>
      throw UnimplementedError();

  List<OAuthProvider> providers = const [];
  String? oauthProviderUsed;

  @override
  Future<List<OAuthProvider>> oauthProviders() async => providers;

  @override
  Future<AppUser> signInWithOAuth2(
    String provider,
    Future<void> Function(Uri url) openUrl,
  ) async {
    oauthProviderUsed = provider;
    return const AppUser(id: 'u1', email: 'staff@example.org');
  }
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  FakeAuthRepository repo, {
  ServerInfo? info,
}) async {
  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWith((ref) async => repo),
      serverInfoProvider.overrideWith((ref) async => info),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: LoginScreen(),
      ),
    ),
  );
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('signs in with the trimmed email and raw password',
      (tester) async {
    final repo = FakeAuthRepository();
    await _pump(tester, repo);

    await tester.enterText(
      find.byType(TextFormField).first,
      '  staff@example.org  ',
    );
    await tester.enterText(find.byType(TextFormField).last, 's3cret');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(repo.lastEmail, 'staff@example.org');
    expect(repo.lastPassword, 's3cret');
  });

  testWidgets('shows an invalid-credentials error on a 400', (tester) async {
    final repo = FakeAuthRepository(
      onSignIn: (_, _) async => throw const RepositoryException(
        'bad',
        kind: RepositoryErrorKind.validation,
        statusCode: 400,
      ),
    );
    await _pump(tester, repo);

    await tester.enterText(
      find.byType(TextFormField).first,
      'staff@example.org',
    );
    await tester.enterText(find.byType(TextFormField).last, 'wrong');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Email or password is incorrect.'), findsOneWidget);
  });

  testWidgets('MFA: password step asks for the one-time code, then completes',
      (tester) async {
    final repo = FakeAuthRepository(
      onSignIn: (_, _) async => throw const MfaRequiredException('mfa-123'),
      onAuthWithOtp: (otpId, code, mfaId) async {
        expect(otpId, 'otp1');
        expect(mfaId, 'mfa-123');
        return const AppUser(id: 'u1', email: 'staff@example.org');
      },
    );
    await _pump(tester, repo);

    await tester.enterText(
      find.byType(TextFormField).first,
      'staff@example.org',
    );
    await tester.enterText(find.byType(TextFormField).last, 's3cret');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    // The form has switched to the OTP step.
    expect(find.text('Enter the code'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, '12345678');
    await tester.tap(find.widgetWithText(FilledButton, 'Verify'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(repo.lastOtpCode, '12345678');
  });

  testWidgets('MFA: a wrong code shows the invalid-code error', (tester) async {
    final repo = FakeAuthRepository(
      onSignIn: (_, _) async => throw const MfaRequiredException('mfa-123'),
      onAuthWithOtp: (_, _, _) async => throw const RepositoryException(
        'bad',
        kind: RepositoryErrorKind.validation,
        statusCode: 400,
      ),
    );
    await _pump(tester, repo);

    await tester.enterText(
      find.byType(TextFormField).first,
      'staff@example.org',
    );
    await tester.enterText(find.byType(TextFormField).last, 's3cret');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, '00000000');
    await tester.tap(find.widgetWithText(FilledButton, 'Verify'));
    await tester.pumpAndSettle();

    expect(find.text('That code is incorrect or has expired.'), findsOneWidget);
  });

  testWidgets('shows the offline error on a network failure', (tester) async {
    final repo = FakeAuthRepository(
      onSignIn: (_, _) async => throw const RepositoryException(
        'net',
        kind: RepositoryErrorKind.network,
      ),
    );
    await _pump(tester, repo);

    await tester.enterText(
      find.byType(TextFormField).first,
      'staff@example.org',
    );
    await tester.enterText(find.byType(TextFormField).last, 'secret');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(find.textContaining("You're offline"), findsOneWidget);
  });

  testWidgets('blocks submission when the form is empty', (tester) async {
    final repo = FakeAuthRepository();
    await _pump(tester, repo);

    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(repo.lastEmail, isNull);
    expect(find.text('This field is required'), findsWidgets);
  });

  testWidgets('submits on Enter in the password field', (tester) async {
    final repo = FakeAuthRepository();
    await _pump(tester, repo);

    await tester.enterText(
      find.byType(TextFormField).first,
      'staff@example.org',
    );
    await tester.enterText(find.byType(TextFormField).last, 's3cret');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(repo.lastEmail, 'staff@example.org');
    expect(repo.lastPassword, 's3cret');
  });

  testWidgets('reflects the server: shows its name and the reset link',
      (tester) async {
    await _pump(
      tester,
      FakeAuthRepository(),
      info: const ServerInfo(
        version: '1.0.0',
        name: 'Wildvogelhilfe',
        auth: ServerAuthOptions(passwordReset: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sign in to Wildvogelhilfe'), findsOneWidget);
    expect(find.text('Forgot password?'), findsOneWidget);
  });

  testWidgets('hides the reset link when the server cannot send mail',
      (tester) async {
    await _pump(
      tester,
      FakeAuthRepository(),
      info: const ServerInfo(
        version: '1.0.0',
        name: 'Federfall',
        auth: ServerAuthOptions(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Forgot password?'), findsNothing);
  });

  testWidgets('renders a provider button and signs in via OAuth2',
      (tester) async {
    final repo = FakeAuthRepository()
      ..providers = const [
        OAuthProvider(name: 'google', displayName: 'Google'),
      ];
    await _pump(
      tester,
      repo,
      info: const ServerInfo(
        version: '1.0.0',
        name: 'Federfall',
        auth: ServerAuthOptions(oauth2: ['google']),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Continue with Google'), findsOneWidget);
    await tester.tap(find.text('Continue with Google'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(repo.oauthProviderUsed, 'google');
  });

  testWidgets('passwordless server shows only the provider button',
      (tester) async {
    final repo = FakeAuthRepository()
      ..providers = const [
        OAuthProvider(name: 'oidc', displayName: 'Single sign-on'),
      ];
    await _pump(
      tester,
      repo,
      info: const ServerInfo(
        version: '1.0.0',
        name: 'Federfall',
        auth: ServerAuthOptions(password: false, oauth2: ['oidc']),
      ),
    );
    await tester.pumpAndSettle();

    // No password sign-in, just the provider button.
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsNothing);
    expect(find.text('Continue with Single sign-on'), findsOneWidget);
  });

  testWidgets('switch server clears the configured URL back to setup',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'federfall.serverUrl': 'https://pigeons.example',
    });
    final repo = FakeAuthRepository();
    final container = await _pump(tester, repo);

    // Configured to begin with (native path reads the stored URL).
    expect(
      await container.read(serverConfigControllerProvider.future),
      isA<ServerConfigured>(),
    );

    await tester.tap(find.text('Use a different server'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      container.read(serverConfigControllerProvider).requireValue,
      isA<ServerUnconfigured>(),
    );
  });
}
