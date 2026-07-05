import 'dart:async';

import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/printing/printer_service.dart';
import 'package:federfall/features/profile/profile_screen.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../printing/fake_printer_service.dart';

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
  AppUser user, {
  FakePrinterService? printerService,
}) async {
  // A configured printer is read via printerSettingsProvider, which reads
  // shared_preferences directly (no override seam) — seed it here so
  // printer-section tests can pre-populate a device the same way an earlier
  // app session would have saved one.
  SharedPreferences.setMockInitialValues(
    printerService == null
        ? {}
        : {
            'printer_device_type': 'network',
            'printer_device_name': 'Epson TM-T88IV',
            'printer_device_host': '10.0.0.5',
            'printer_device_port': 9100,
          },
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWith((ref) async => repo),
        currentUserProvider.overrideWith((ref) async => user),
        if (printerService != null)
          printerServiceProvider.overrideWithValue(printerService),
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

    await tester.scrollUntilVisible(
      find.widgetWithText(FilledButton, 'Sign out'),
      100,
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

    await tester.scrollUntilVisible(
      find.widgetWithText(FilledButton, 'Sign out'),
      100,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(repo.signedOut, isFalse);
  });

  testWidgets('shows a prompt to configure when no printer is saved', (
    tester,
  ) async {
    await _pump(
      tester,
      FakeAuthRepository(),
      const AppUser(id: 'u1', email: 'c@x.org', role: UserRole.carer),
    );

    expect(find.text('No printer configured'), findsOneWidget);
    expect(find.text('Test print'), findsNothing);
  });

  testWidgets('shows the saved device and offers a test print', (
    tester,
  ) async {
    final printer = FakePrinterService();
    await _pump(
      tester,
      FakeAuthRepository(),
      const AppUser(id: 'u1', email: 'c@x.org', role: UserRole.carer),
      printerService: printer,
    );

    expect(find.textContaining('Epson TM-T88IV'), findsOneWidget);
    expect(find.textContaining('10.0.0.5:9100'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Test print'), 100);
    await tester.tap(find.text('Test print'));
    await tester.pumpAndSettle();

    expect(printer.connected, hasLength(1));
    expect(printer.testTicketsPrinted, hasLength(1));
    expect(printer.disconnectCalls, 1);
    expect(find.text('Test print sent'), findsOneWidget);
  });

  testWidgets('a failed test print surfaces an error and still disconnects', (
    tester,
  ) async {
    final printer = FakePrinterService()
      ..connectError = Exception('unreachable');
    await _pump(
      tester,
      FakeAuthRepository(),
      const AppUser(id: 'u1', email: 'c@x.org', role: UserRole.carer),
      printerService: printer,
    );

    await tester.scrollUntilVisible(find.text('Test print'), 100);
    await tester.tap(find.text('Test print'));
    await tester.pumpAndSettle();

    expect(printer.testTicketsPrinted, isEmpty);
    expect(printer.disconnectCalls, 1);
    expect(find.text('Test print sent'), findsNothing);
  });

  testWidgets('removing the printer asks for confirmation first', (
    tester,
  ) async {
    final printer = FakePrinterService();
    await _pump(
      tester,
      FakeAuthRepository(),
      const AppUser(id: 'u1', email: 'c@x.org', role: UserRole.carer),
      printerService: printer,
    );

    await tester.tap(find.byTooltip('Remove printer'));
    await tester.pumpAndSettle();
    expect(find.text('Remove printer?'), findsOneWidget);

    // Cancelling keeps the device configured.
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Epson TM-T88IV'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove printer'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Remove printer'));
    await tester.pumpAndSettle();

    expect(find.text('No printer configured'), findsOneWidget);
  });
}
