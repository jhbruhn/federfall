import 'package:federfall_models/src/converters.dart';
import 'package:federfall_models/src/enums.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:pocketbase/pocketbase.dart';

part 'app_user.freezed.dart';

/// A staff member of an organisation (the PocketBase `users` auth collection).
///
/// Named [AppUser] rather than `User` to avoid clashing with framework types
/// and to make clear it models the app's own staff, not the finder PII.
@freezed
abstract class AppUser with _$AppUser {
  const factory AppUser({
    required String id,
    required String email,
    String? name,
    UserRole? role,
    String? org,
    @Default(false) bool isActive,
    String? invitedBy,
    String? phone,
    @Default(false) bool verified,
    @Default(false) bool mfaEnabled,
    DateTime? created,
    DateTime? updated,
  }) = _AppUser;

  factory AppUser.fromRecord(RecordModel r) {
    final d = r.data;
    return AppUser(
      id: r.id,
      email: pbString(d['email']) ?? '',
      name: pbString(d['name']),
      role: UserRole.fromWire(d['role']),
      org: pbString(d['org']),
      isActive: pbBool(d['is_active']),
      invitedBy: pbString(d['invited_by']),
      phone: pbString(d['phone']),
      verified: pbBool(d['verified']),
      mfaEnabled: pbBool(d['mfa_enabled']),
      created: pbDate(d['created']),
      updated: pbDate(d['updated']),
    );
  }
}
