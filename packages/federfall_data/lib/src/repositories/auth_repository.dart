import 'dart:math';

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
  ///
  /// When the account has MFA enabled the password is only the first factor:
  /// PocketBase withholds the token and this throws [MfaRequiredException]
  /// carrying an `mfaId`. Complete the login with [requestOtp] + [authWithOtp].
  Future<AppUser> signIn(String email, String password);

  /// Sends a one-time password to [email] (the MFA second factor) and returns
  /// the `otpId` to pair with the emailed code in [authWithOtp].
  Future<String> requestOtp(String email);

  /// Completes an MFA login with the emailed [code]: [otpId] from [requestOtp]
  /// and [mfaId] from the [MfaRequiredException] thrown by [signIn].
  Future<AppUser> authWithOtp({
    required String otpId,
    required String code,
    required String mfaId,
  });

  /// Toggles MFA (email-OTP second factor) for the signed-in user, refreshing
  /// the session so [currentUser]/[changes] reflect it immediately.
  Future<AppUser> setMfaEnabled({required bool enabled});

  /// Refreshes the session token; returns the user, or `null` if it could not
  /// be refreshed (e.g. expired/revoked).
  Future<AppUser?> refresh();

  /// Clears the session.
  void signOut();

  /// Invites a new member (supervisor action): creates their `users` record
  /// (active, with a throwaway password) and triggers a password-reset email
  /// so the invitee sets their own password. Org and inviter are taken from
  /// the current session.
  Future<AppUser> inviteUser({
    required String email,
    required UserRole role,
    String? name,
  });

  /// Updates the signed-in user's own profile (name/phone) and refreshes the
  /// session so [currentUser]/[changes] reflect the new values immediately.
  Future<AppUser> updateProfile({String? name, String? phone});

  /// Requests a password-reset email for [email] (used by the invite flow and
  /// "forgot password").
  Future<void> requestPasswordReset(String email);

  /// Completes a password reset with the emailed [token].
  Future<void> confirmPasswordReset(String token, String password);
}

/// Thrown by [AuthRepository.signIn] when the password was correct but the
/// account has MFA enabled, so a second factor is still required. Carries the
/// [mfaId] that links the password step to the OTP step.
class MfaRequiredException implements Exception {
  const MfaRequiredException(this.mfaId);

  /// PocketBase's identifier for this in-progress MFA attempt.
  final String mfaId;
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
      // A correct password on an MFA account returns 401 with an mfaId rather
      // than a token: surface that as a distinct control-flow signal.
      final mfaId = e.response['mfaId'];
      if (mfaId is String && mfaId.isNotEmpty) {
        throw MfaRequiredException(mfaId);
      }
      throw RepositoryException.fromClient(e);
    }
  }

  @override
  Future<String> requestOtp(String email) async {
    try {
      final res = await _users.requestOTP(email);
      return res.otpId;
    } on ClientException catch (e) {
      throw RepositoryException.fromClient(e);
    }
  }

  @override
  Future<AppUser> authWithOtp({
    required String otpId,
    required String code,
    required String mfaId,
  }) async {
    try {
      // The mfaId links this OTP (second factor) to the earlier password step.
      final auth = await _users.authWithOTP(
        otpId,
        code,
        body: {'mfaId': mfaId},
      );
      return AppUser.fromRecord(auth.record);
    } on ClientException catch (e) {
      throw RepositoryException.fromClient(e);
    }
  }

  @override
  Future<AppUser> setMfaEnabled({required bool enabled}) async {
    final record = pb.authStore.record;
    if (record == null) {
      throw const RepositoryException('not signed in');
    }
    try {
      final updated = await _users.update(
        record.id,
        body: {'mfa_enabled': enabled},
      );
      pb.authStore.save(pb.authStore.token, updated);
      return AppUser.fromRecord(updated);
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

  @override
  Future<AppUser> inviteUser({
    required String email,
    required UserRole role,
    String? name,
  }) async {
    final inviter = pb.authStore.record;
    final org = inviter?.get<String>('org');
    if (org == null || org.isEmpty) {
      throw const RepositoryException('the inviting user has no organisation');
    }

    // Throwaway password: required by PocketBase on create, never used — the
    // invitee sets their own via the reset email below.
    final tempPassword = _randomPassword();
    try {
      final record = await _users.create(
        body: {
          'email': email,
          if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
          'role': role.wire,
          'org': org,
          'is_active': true,
          'password': tempPassword,
          'passwordConfirm': tempPassword,
          if (inviter != null) 'invited_by': inviter.id,
        },
      );
      await _users.requestPasswordReset(email);
      return AppUser.fromRecord(record);
    } on ClientException catch (e) {
      throw RepositoryException.fromClient(e);
    }
  }

  @override
  Future<AppUser> updateProfile({String? name, String? phone}) async {
    final record = pb.authStore.record;
    if (record == null) {
      throw const RepositoryException('not signed in');
    }
    try {
      final updated = await _users.update(
        record.id,
        body: {
          'name': name?.trim() ?? '',
          'phone': phone?.trim() ?? '',
        },
      );
      // Persist the refreshed record into the auth store so currentUser and
      // the changes stream emit the new values without a re-login.
      pb.authStore.save(pb.authStore.token, updated);
      return AppUser.fromRecord(updated);
    } on ClientException catch (e) {
      throw RepositoryException.fromClient(e);
    }
  }

  @override
  Future<void> requestPasswordReset(String email) async {
    try {
      await _users.requestPasswordReset(email);
    } on ClientException catch (e) {
      throw RepositoryException.fromClient(e);
    }
  }

  @override
  Future<void> confirmPasswordReset(String token, String password) async {
    try {
      await _users.confirmPasswordReset(token, password, password);
    } on ClientException catch (e) {
      throw RepositoryException.fromClient(e);
    }
  }

  String _randomPassword() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789';
    final rnd = Random.secure();
    return List.generate(24, (_) => chars[rnd.nextInt(chars.length)]).join();
  }
}
