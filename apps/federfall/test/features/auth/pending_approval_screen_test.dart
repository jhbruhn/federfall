import 'package:federfall/core/auth/auth_status.dart';
import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/auth/pending_approval_screen.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class _FakeAuthStatus extends AuthStatus {
  @override
  Future<bool> build() async => false;
}

void main() {
  late MockAuthRepository auth;

  setUp(() {
    auth = MockAuthRepository();
    when(() => auth.refresh()).thenAnswer((_) async => null);
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWith((ref) async => auth),
          authStatusProvider.overrideWith(_FakeAuthStatus.new),
          currentUserProvider.overrideWith(
            (ref) async => const AppUser(id: 'u1', email: 'guest@x.org'),
          ),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PendingApprovalScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the pending message and the signed-in email', (
    tester,
  ) async {
    await pump(tester);

    expect(find.text('Awaiting access'), findsOneWidget);
    expect(find.text('guest@x.org'), findsOneWidget);
  });

  testWidgets('checking again refreshes the session', (tester) async {
    await pump(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Check again'));
    await tester.pumpAndSettle();

    verify(() => auth.refresh()).called(1);
  });

  testWidgets('signs out after confirming', (tester) async {
    when(() => auth.signOut()).thenReturn(null);
    await pump(tester);

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    expect(find.text('Sign out of this device?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Sign out').last);
    await tester.pumpAndSettle();

    verify(() => auth.signOut()).called(1);
  });
}
