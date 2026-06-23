import 'package:federfall_data/src/repository_exception.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:pocketbase/pocketbase.dart';

/// Authentication and session access for the `users` collection.
abstract interface class AuthRepository {
  /// Whether a (loosely) valid session token is present.
  bool get isSignedIn;

  /// The currently authenticated user, or `null` when signed out.
  AppUser? get currentUser;

  /// Emits the current user on every auth change (login/logout/refresh).
  Stream<AppUser?> get changes;

  /// Signs in with email + password, returning the authenticated user.
  Future<AppUser> signIn(String email, String password);

  /// Refreshes the session token; returns the user, or `null` if it could not
  /// be refreshed (e.g. expired/revoked).
  Future<AppUser?> refresh();

  /// Clears the session.
  void signOut();
}

/// PocketBase-backed [AuthRepository].
class PbAuthRepository implements AuthRepository {
  PbAuthRepository(this.pb);

  final PocketBase pb;

  RecordService get _users => pb.collection('users');

  @override
  bool get isSignedIn => pb.authStore.isValid;

  @override
  AppUser? get currentUser {
    final record = pb.authStore.record;
    return record == null ? null : AppUser.fromRecord(record);
  }

  @override
  Stream<AppUser?> get changes => pb.authStore.onChange.map(
    (e) => e.record == null ? null : AppUser.fromRecord(e.record!),
  );

  @override
  Future<AppUser> signIn(String email, String password) async {
    try {
      final auth = await _users.authWithPassword(email, password);
      return AppUser.fromRecord(auth.record);
    } on ClientException catch (e) {
      throw RepositoryException.fromClient(e);
    }
  }

  @override
  Future<AppUser?> refresh() async {
    if (!pb.authStore.isValid) return null;
    try {
      final auth = await _users.authRefresh();
      return AppUser.fromRecord(auth.record);
    } on ClientException catch (e) {
      // An invalid/expired token clears the store; treat as signed out.
      if (e.statusCode == 401 || e.statusCode == 403) {
        pb.authStore.clear();
        return null;
      }
      throw RepositoryException.fromClient(e);
    }
  }

  @override
  void signOut() => pb.authStore.clear();
}
