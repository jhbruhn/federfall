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
}
