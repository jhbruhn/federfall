import 'dart:async';

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

Future<void> _pump(
  WidgetTester tester, {
  required FakeAuthRepository repo,
  required List<Case> cases,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWith((ref) async => repo),
        myCasesProvider.overrideWith((ref) async => cases),
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
    await _pump(tester, repo: FakeAuthRepository(), cases: const []);

    expect(find.text('No cases yet'), findsOneWidget);
  });

  testWidgets('lists my cases by case number', (tester) async {
    await _pump(
      tester,
      repo: FakeAuthRepository(),
      cases: const [
        Case(id: 'c1', animal: 'a1', caseNumber: '2026-001'),
      ],
    );

    expect(find.text('2026-001'), findsOneWidget);
  });

  testWidgets('signs out from the app bar action', (tester) async {
    final repo = FakeAuthRepository();
    await _pump(tester, repo: repo, cases: const []);

    await tester.tap(find.byTooltip('Sign out'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(repo.signedOut, isTrue);
  });
}
