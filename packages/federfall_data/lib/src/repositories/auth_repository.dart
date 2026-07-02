import 'dart:async';
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

  /// The OAuth2 providers the server offers, in the order to present them.
  Future<List<OAuthProvider>> oauthProviders();

  /// Signs in via the OAuth2 [provider]. [openUrl] receives the provider's
  /// authorization URL — the caller opens it (a browser tab / external app); the
  /// flow then completes over PocketBase's realtime channel and the auth store
  /// is updated, so no app-side deep-link wiring is needed.
  Future<AppUser> signInWithOAuth2(
    String provider,
    Future<void> Function(Uri url) openUrl,
  );

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
  ///
  /// Throws [InviteEmailFailedException] when the account was created but the
  /// reset email failed — the caller should offer to resend it rather than
  /// retry the whole invite.
  Future<AppUser> inviteUser({
    required String email,
    required UserRole role,
    String? name,
  });

  /// Updates the signed-in user's own profile (name/phone) and refreshes the
  /// session so [currentUser]/[changes] reflect the new values immediately.
  ///
  /// Partial update: a `null` argument leaves that field unchanged; pass an
  /// empty string to clear it.
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

/// Thrown by [AuthRepository.inviteUser] when the account WAS created but the
/// password-reset email could not be sent (mailer down, timeout). The invite
/// is half-done: retrying it would fail with a duplicate-email error, and the
/// invitee holds an account with an unknowable throwaway password. Callers
/// should surface "account created, resend the reset email" — e.g. via
/// [AuthRepository.requestPasswordReset] — instead of a generic failure.
class InviteEmailFailedException implements Exception {
  const InviteEmailFailedException(this.user);

  /// The user record that was created before the email step failed.
  final AppUser user;
}

/// An OAuth2 provider the server offers, for rendering a sign-in button.
class OAuthProvider {
  const OAuthProvider({required this.name, required this.displayName});

  /// The PocketBase provider name (e.g. `google`, `oidc`) — pass to
  /// [AuthRepository.signInWithOAuth2].
  final String name;

  /// The human label for the button (e.g. `Google`, or the configured OIDC
  /// display name); falls back to [name] when the server gives none.
  final String displayName;
}

/// PocketBase-backed [AuthRepository].
class PbAuthRepository implements AuthRepository {
  PbAuthRepository(
    this.pb, {
    this.networkTimeout = const Duration(seconds: 15),
  });

  final PocketBase pb;

  /// Caps each request so an unreachable server fails fast with a network
  /// error instead of hanging on the OS TCP timeout (minutes). Sign-in is the
  /// very first call a user makes against a possibly-wrong server URL, so it
  /// must fail fast like every other repository call. Not applied to the
  /// OAuth2 flow, which legitimately waits on user interaction.
  final Duration networkTimeout;

  RecordService get _users => pb.collection('users');

  /// Caps [op] at [networkTimeout], mapping a timeout to the same network
  /// [RepositoryException] the other repositories throw.
  Future<R> _withTimeout<R>(Future<R> Function() op) async {
    try {
      return await op().timeout(networkTimeout);
    } on TimeoutException {
      throw const RepositoryException(
        'Could not reach the server',
        kind: RepositoryErrorKind.network,
      );
    }
  }

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
      final auth = await _withTimeout(
        () => _users.authWithPassword(email, password),
      );
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
  Future<List<OAuthProvider>> oauthProviders() async {
    try {
      final methods = await _withTimeout(_users.listAuthMethods);
      return methods.oauth2.providers
          .map(
            (p) => OAuthProvider(
              name: p.name,
              displayName: p.displayName.isNotEmpty ? p.displayName : p.name,
            ),
          )
          .toList(growable: false);
    } on ClientException catch (e) {
      throw RepositoryException.fromClient(e);
    }
  }

  @override
  Future<AppUser> signInWithOAuth2(
    String provider,
    Future<void> Function(Uri url) openUrl,
  ) async {
    try {
      // Deliberately NOT capped at networkTimeout: this waits for the user to
      // complete the provider's flow in a browser, which can take minutes.
      final auth = await _users.authWithOAuth2(
        provider,
        (url) => openUrl(url),
      );
      return AppUser.fromRecord(auth.record);
    } on ClientException catch (e) {
      throw RepositoryException.fromClient(e);
    }
  }

  @override
  Future<String> requestOtp(String email) async {
    try {
      final res = await _withTimeout(() => _users.requestOTP(email));
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
      final auth = await _withTimeout(
        () => _users.authWithOTP(otpId, code, body: {'mfaId': mfaId}),
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
      final updated = await _withTimeout(
        () => _users.update(record.id, body: {'mfa_enabled': enabled}),
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
      final auth = await _withTimeout(_users.authRefresh);
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
    final RecordModel record;
    try {
      record = await _withTimeout(
        () => _users.create(
          body: {
            'email': email,
            // Visible to fellow org members so the team roster shows it.
            'emailVisibility': true,
            if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
            'role': role.wire,
            'org': org,
            'is_active': true,
            'password': tempPassword,
            'passwordConfirm': tempPassword,
            if (inviter != null) 'invited_by': inviter.id,
          },
        ),
      );
    } on ClientException catch (e) {
      throw RepositoryException.fromClient(e);
    }

    // The account now exists; a reset-email failure past this point must NOT
    // surface as a plain "invite failed" — retrying the invite would hit a
    // duplicate-email error with no hint that resending the reset email is the
    // fix. Signal the partial state distinctly instead.
    final user = AppUser.fromRecord(record);
    try {
      await _withTimeout(() => _users.requestPasswordReset(email));
    } on Exception {
      throw InviteEmailFailedException(user);
    }
    return user;
  }

  @override
  Future<AppUser> updateProfile({String? name, String? phone}) async {
    final record = pb.authStore.record;
    if (record == null) {
      throw const RepositoryException('not signed in');
    }
    try {
      final updated = await _withTimeout(
        () => _users.update(
          record.id,
          // Null-aware elements: an omitted argument means "leave unchanged",
          // never "clear" — an empty string is how a caller clears a field.
          body: {
            'name': ?name?.trim(),
            'phone': ?phone?.trim(),
          },
        ),
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
      await _withTimeout(() => _users.requestPasswordReset(email));
    } on ClientException catch (e) {
      throw RepositoryException.fromClient(e);
    }
  }

  @override
  Future<void> confirmPasswordReset(String token, String password) async {
    try {
      await _withTimeout(
        () => _users.confirmPasswordReset(token, password, password),
      );
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
