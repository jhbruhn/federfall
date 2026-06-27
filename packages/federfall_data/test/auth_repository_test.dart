import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:test/test.dart';

class _MockPb extends Mock implements PocketBase {}

class _MockService extends Mock implements RecordService {}

class _MockAuthStore extends Mock implements AuthStore {}

void main() {
  late _MockPb pb;
  late _MockService users;
  late _MockAuthStore store;
  late PbAuthRepository repo;

  setUp(() {
    pb = _MockPb();
    users = _MockService();
    store = _MockAuthStore();
    when(() => pb.collection('users')).thenReturn(users);
    when(() => pb.authStore).thenReturn(store);
    repo = PbAuthRepository(pb);
  });

  test('signIn returns the mapped authenticated user', () async {
    final record = RecordModel({
      'id': 'usr1',
      'email': 'carer@example.de',
      'role': 'carer',
    });
    when(() => users.authWithPassword('carer@example.de', 'pw'))
        .thenAnswer((_) async => RecordAuth(token: 't', record: record));

    final user = await repo.signIn('carer@example.de', 'pw');

    expect(user.id, 'usr1');
    expect(user.email, 'carer@example.de');
    expect(user.role, UserRole.carer);
  });

  test('signIn translates auth failure', () async {
    when(() => users.authWithPassword(any(), any()))
        .thenThrow(ClientException(statusCode: 400));

    expect(
      () => repo.signIn('x', 'y'),
      throwsA(
        isA<RepositoryException>()
            .having((e) => e.kind, 'kind', RepositoryErrorKind.validation),
      ),
    );
  });

  test('refresh returns null and clears store on 401', () async {
    when(() => store.isValid).thenReturn(true);
    when(() => store.clear()).thenReturn(null);
    when(() => users.authRefresh()).thenThrow(ClientException(statusCode: 401));

    expect(await repo.refresh(), isNull);
    verify(() => store.clear()).called(1);
  });

  test('currentUser reflects the auth store record', () {
    when(() => store.record).thenReturn(
      RecordModel({'id': 'usr2', 'email': 'a@b.de', 'role': 'supervisor'}),
    );

    expect(repo.currentUser?.role, UserRole.supervisor);
  });

  test('inviteUser creates the user in the inviter org and sends a reset',
      () async {
    when(() => store.record).thenReturn(
      RecordModel({'id': 'sup1', 'org': 'org1', 'role': 'supervisor'}),
    );
    when(() => users.create(body: any(named: 'body'))).thenAnswer(
      (_) async => RecordModel({'id': 'new1', 'email': 'new@example.de'}),
    );
    when(() => users.requestPasswordReset(any())).thenAnswer((_) async {});

    final created = await repo.inviteUser(
      email: 'new@example.de',
      role: UserRole.carer,
      name: 'Neu',
    );

    expect(created.id, 'new1');
    final body = verify(() => users.create(body: captureAny(named: 'body')))
        .captured
        .single as Map<String, dynamic>;
    expect(body['email'], 'new@example.de');
    expect(body['role'], 'carer');
    expect(body['org'], 'org1');
    expect(body['is_active'], true);
    expect(body['invited_by'], 'sup1');
    expect(body['name'], 'Neu');
    expect(body['password'], isNotEmpty);
    expect(body['password'], body['passwordConfirm']);
    verify(() => users.requestPasswordReset('new@example.de')).called(1);
  });

  test('inviteUser fails when the inviter has no org', () async {
    when(() => store.record)
        .thenReturn(RecordModel({'id': 'sup1', 'role': 'supervisor'}));

    expect(
      () => repo.inviteUser(email: 'x@y.de', role: UserRole.carer),
      throwsA(isA<RepositoryException>()),
    );
  });

  test('confirmPasswordReset passes the token and password twice', () async {
    when(() => users.confirmPasswordReset(any(), any(), any()))
        .thenAnswer((_) async {});

    await repo.confirmPasswordReset('tok123', 'newpass');

    verify(() => users.confirmPasswordReset('tok123', 'newpass', 'newpass'))
        .called(1);
  });

  test('isSignedIn and signOut delegate to the auth store', () {
    when(() => store.isValid).thenReturn(true);
    when(() => store.clear()).thenReturn(null);

    expect(repo.isSignedIn, isTrue);
    repo.signOut();
    verify(() => store.clear()).called(1);
  });

  test('signIn surfaces an MFA challenge as MfaRequiredException', () async {
    when(() => users.authWithPassword(any(), any())).thenThrow(
      ClientException(
        statusCode: 401,
        response: const {'mfaId': 'mfa123'},
      ),
    );

    expect(
      () => repo.signIn('a@b.de', 'pw'),
      throwsA(
        isA<MfaRequiredException>().having((e) => e.mfaId, 'mfaId', 'mfa123'),
      ),
    );
  });

  test('oauthProviders maps providers, falling back to name as label',
      () async {
    when(() => users.listAuthMethods()).thenAnswer(
      (_) async => AuthMethodsList(
        oauth2: AuthMethodOAuth2(
          providers: [
            AuthMethodProvider(name: 'google', displayName: 'Google'),
            AuthMethodProvider(name: 'oidc'),
          ],
        ),
      ),
    );

    final providers = await repo.oauthProviders();

    expect(providers.map((p) => p.name), ['google', 'oidc']);
    expect(providers.map((p) => p.displayName), ['Google', 'oidc']);
  });

  test('oauthProviders translates a client error', () async {
    when(() => users.listAuthMethods())
        .thenThrow(ClientException(statusCode: 500));

    expect(repo.oauthProviders(), throwsA(isA<RepositoryException>()));
  });

  test('signInWithOAuth2 returns the mapped user and drives the url callback',
      () async {
    final record = RecordModel({'id': 'oa1', 'email': 'g@example.de'});
    when(
      () => users.authWithOAuth2(any(), any()),
    ).thenAnswer((_) async => RecordAuth(token: 't', record: record));

    final user = await repo.signInWithOAuth2('google', (_) async {});

    expect(user.id, 'oa1');
    verify(() => users.authWithOAuth2('google', any())).called(1);
  });

  test('requestOtp returns the otpId', () async {
    when(() => users.requestOTP('a@b.de'))
        .thenAnswer((_) async => OTPResponse(otpId: 'otp1'));

    expect(await repo.requestOtp('a@b.de'), 'otp1');
  });

  test('authWithOtp links the otp to the earlier password step via mfaId',
      () async {
    final record = RecordModel({'id': 'usr1', 'email': 'a@b.de'});
    when(
      () => users.authWithOTP('otp1', '123456', body: any(named: 'body')),
    ).thenAnswer((_) async => RecordAuth(token: 't', record: record));

    final user =
        await repo.authWithOtp(otpId: 'otp1', code: '123456', mfaId: 'mfa1');

    expect(user.id, 'usr1');
    final body = verify(
      () => users.authWithOTP(
        'otp1',
        '123456',
        body: captureAny(named: 'body'),
      ),
    ).captured.single as Map<String, dynamic>;
    expect(body['mfaId'], 'mfa1');
  });

  test('setMfaEnabled updates the record and re-saves the auth store',
      () async {
    when(() => store.record)
        .thenReturn(RecordModel({'id': 'usr1', 'email': 'a@b.de'}));
    when(() => store.token).thenReturn('tok');
    when(() => store.save(any(), any())).thenReturn(null);
    final updated =
        RecordModel({'id': 'usr1', 'email': 'a@b.de', 'mfa_enabled': true});
    when(() => users.update('usr1', body: any(named: 'body')))
        .thenAnswer((_) async => updated);

    final user = await repo.setMfaEnabled(enabled: true);

    expect(user.mfaEnabled, isTrue);
    final body = verify(
      () => users.update('usr1', body: captureAny(named: 'body')),
    ).captured.single as Map<String, dynamic>;
    expect(body['mfa_enabled'], true);
    verify(() => store.save('tok', updated)).called(1);
  });

  test('setMfaEnabled rejects when nobody is signed in', () async {
    when(() => store.record).thenReturn(null);

    expect(
      () => repo.setMfaEnabled(enabled: true),
      throwsA(isA<RepositoryException>()),
    );
  });

  test('updateProfile trims name/phone and persists into the store', () async {
    when(() => store.record)
        .thenReturn(RecordModel({'id': 'usr1', 'email': 'a@b.de'}));
    when(() => store.token).thenReturn('tok');
    when(() => store.save(any(), any())).thenReturn(null);
    final updated = RecordModel(
      {'id': 'usr1', 'email': 'a@b.de', 'name': 'Mara', 'phone': '123'},
    );
    when(() => users.update('usr1', body: any(named: 'body')))
        .thenAnswer((_) async => updated);

    final user = await repo.updateProfile(name: '  Mara  ', phone: ' 123 ');

    expect(user.name, 'Mara');
    final body = verify(
      () => users.update('usr1', body: captureAny(named: 'body')),
    ).captured.single as Map<String, dynamic>;
    expect(body['name'], 'Mara');
    expect(body['phone'], '123');
    verify(() => store.save('tok', updated)).called(1);
  });

  test('updateProfile rejects when nobody is signed in', () async {
    when(() => store.record).thenReturn(null);

    expect(
      () => repo.updateProfile(name: 'x'),
      throwsA(isA<RepositoryException>()),
    );
  });

  test('refresh returns the mapped user while the token is valid', () async {
    when(() => store.isValid).thenReturn(true);
    final record = RecordModel({'id': 'usr1', 'email': 'a@b.de'});
    when(() => users.authRefresh())
        .thenAnswer((_) async => RecordAuth(token: 't', record: record));

    final user = await repo.refresh();

    expect(user?.id, 'usr1');
  });

  test('refresh is a no-op (null) when there is no valid token', () async {
    when(() => store.isValid).thenReturn(false);

    expect(await repo.refresh(), isNull);
    verifyNever(() => users.authRefresh());
  });

  test('requestPasswordReset delegates to the users service', () async {
    when(() => users.requestPasswordReset('a@b.de')).thenAnswer((_) async {});

    await repo.requestPasswordReset('a@b.de');

    verify(() => users.requestPasswordReset('a@b.de')).called(1);
  });
}
