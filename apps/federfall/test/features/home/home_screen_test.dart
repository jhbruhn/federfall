import 'dart:async';

import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/features/home/home_screen.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeAuthRepository implements AuthRepository {
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
  void signOut() {}
}

Future<void> _pump(
  WidgetTester tester, {
  List<Case> cases = const [],
  AppUser? user,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider
            .overrideWith((ref) async => FakeAuthRepository()),
        myCasesProvider.overrideWith((ref) async => cases),
        if (user != null)
          currentUserProvider.overrideWith((ref) async => user),
      ],
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: HomeScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the empty state when there are no cases', (tester) async {
    await _pump(tester);
    expect(find.text('No cases yet'), findsOneWidget);
  });

  testWidgets('lists my cases by case number', (tester) async {
    await _pump(
      tester,
      cases: const [Case(id: 'c1', animal: 'a1', caseNumber: '2026-001')],
    );
    expect(find.text('2026-001'), findsOneWidget);
  });

  testWidgets('always offers the profile action, hides admin for a carer',
      (tester) async {
    await _pump(
      tester,
      user: const AppUser(id: 'u1', email: 'c@x.org', role: UserRole.carer),
    );

    expect(find.byTooltip('Profile'), findsOneWidget);
    expect(find.byTooltip('Administration'), findsNothing);
  });

  testWidgets('shows the admin action for a supervisor', (tester) async {
    await _pump(
      tester,
      user: const AppUser(
        id: 'u1',
        email: 's@x.org',
        role: UserRole.supervisor,
      ),
    );

    expect(find.byTooltip('Administration'), findsOneWidget);
  });
}
