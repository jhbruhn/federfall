import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/admin/admin_providers.dart';
import 'package:federfall/features/admin/admin_screen.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockUsersRepo extends Mock implements PbUsersRepository {}

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
  Future<AppUser> updateProfile({String? name, String? phone}) async =>
      throw UnimplementedError();

  @override
  Future<void> requestPasswordReset(String email) async {}
  @override
  Future<void> confirmPasswordReset(String token, String password) async {}
}

Future<void> _pump(
  WidgetTester tester, {
  required FakeAuthRepository repo,
  required UserRole role,
  List<AppUser> members = const [],
  PbUsersRepository? users,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWith((ref) async => repo),
        currentUserProvider.overrideWith(
          (ref) async => AppUser(id: 'u1', email: 'me@x.org', role: role),
        ),
        orgMembersProvider.overrideWith((ref) async => members),
        if (users != null)
          usersRepositoryProvider.overrideWith((ref) async => users),
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
  setUpAll(() => registerFallbackValue(<String, dynamic>{}));

  testWidgets('a carer is shown an unauthorized message', (tester) async {
    await _pump(tester, repo: FakeAuthRepository(), role: UserRole.carer);
    expect(find.text('You are not authorized to do that'), findsOneWidget);
  });

  testWidgets('a supervisor sees the team roster with status badges',
      (tester) async {
    await _pump(
      tester,
      repo: FakeAuthRepository(),
      role: UserRole.supervisor,
      members: const [
        AppUser(
          id: 'm1',
          email: 'ada@x.org',
          name: 'Ada',
          role: UserRole.coordinator,
          isActive: true,
          verified: true,
        ),
        AppUser(
          id: 'm2',
          email: 'pending@x.org',
          role: UserRole.carer,
          isActive: true,
        ),
        AppUser(
          id: 'm3',
          email: 'old@x.org',
          name: 'Old',
          role: UserRole.carer,
        ),
      ],
    );

    expect(find.text('Ada'), findsOneWidget);
    expect(find.textContaining('Coordinator'), findsOneWidget);
    // m2 is active but not verified → invite pending.
    expect(find.text('Invite pending'), findsOneWidget);
    // m3 is not active → inactive.
    expect(find.text('Inactive'), findsOneWidget);
  });

  testWidgets('an empty roster shows the empty state', (tester) async {
    await _pump(tester, repo: FakeAuthRepository(), role: UserRole.supervisor);
    expect(find.text('No team members yet.'), findsOneWidget);
  });

  testWidgets('inviting from the FAB calls the repo and confirms',
      (tester) async {
    final repo = FakeAuthRepository();
    await _pump(tester, repo: repo, role: UserRole.supervisor);

    // Open the invite sheet from the FAB.
    await tester.tap(
      find.widgetWithText(FloatingActionButton, 'Invite a member'),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'new@x.org');
    await tester.tap(find.widgetWithText(FilledButton, 'Send invite'));
    await tester.pumpAndSettle();

    expect(repo.invitedEmail, 'new@x.org');
    expect(repo.invitedRole, UserRole.carer);
    expect(find.text('Invite sent to new@x.org.'), findsOneWidget);
  });

  testWidgets('changing a member role saves via the repo', (tester) async {
    final users = MockUsersRepo();
    when(() => users.update(any(), any()))
        .thenAnswer((_) async => const AppUser(id: 'm1', email: 'ada@x.org'));

    await _pump(
      tester,
      repo: FakeAuthRepository(),
      role: UserRole.supervisor,
      users: users,
      members: const [
        AppUser(
          id: 'm1',
          email: 'ada@x.org',
          name: 'Ada',
          role: UserRole.carer,
          isActive: true,
          verified: true,
        ),
      ],
    );

    await tester.tap(find.text('Ada'));
    await tester.pumpAndSettle();

    // Promote to coordinator, then save.
    await tester.tap(find.text('Carer').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Coordinator').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final captured =
        verify(() => users.update('m1', captureAny())).captured.single;
    expect((captured as Map)['role'], 'coordinator');
  });

  testWidgets('opening your own account hides remove and shows a note',
      (tester) async {
    final users = MockUsersRepo();
    await _pump(
      tester,
      repo: FakeAuthRepository(),
      role: UserRole.supervisor,
      users: users,
      members: const [
        AppUser(
          id: 'u1',
          email: 'me@x.org',
          name: 'Me',
          role: UserRole.supervisor,
          isActive: true,
          verified: true,
        ),
      ],
    );

    await tester.tap(find.text('Me'));
    await tester.pumpAndSettle();

    expect(find.textContaining('your own account'), findsOneWidget);
    expect(find.text('Remove member'), findsNothing);
  });

  testWidgets('removing a member confirms and deletes', (tester) async {
    final users = MockUsersRepo();
    when(() => users.delete(any())).thenAnswer((_) async {});

    await _pump(
      tester,
      repo: FakeAuthRepository(),
      role: UserRole.supervisor,
      users: users,
      members: const [
        AppUser(
          id: 'm1',
          email: 'ada@x.org',
          name: 'Ada',
          role: UserRole.carer,
          isActive: true,
          verified: true,
        ),
      ],
    );

    await tester.tap(find.text('Ada'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Remove member'));
    await tester.pumpAndSettle();
    // Confirm in the dialog.
    await tester.tap(find.widgetWithText(TextButton, 'Remove member').last);
    await tester.pumpAndSettle();

    verify(() => users.delete('m1')).called(1);
  });
}
