import 'dart:async';

import 'package:federfall/core/server/server_config.dart';
import 'package:federfall/core/server/server_config_controller.dart';
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
  FakeAuthRepository({this.onSignIn});

  final Future<AppUser> Function(String email, String password)? onSignIn;

  String? lastEmail;
  String? lastPassword;
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
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  FakeAuthRepository repo,
) async {
  final container = ProviderContainer(
    overrides: [authRepositoryProvider.overrideWith((ref) async => repo)],
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
