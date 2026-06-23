import 'package:federfall/l10n/gen/app_localizations.dart';
import 'package:federfall_models/federfall_models.dart';

/// Role-derived UI capabilities (FED-3.3).
///
/// These gate what the UI *offers* so users aren't shown actions they can't
/// perform. They are NOT the security boundary — the PocketBase API access
/// rules (FED-1.11) are, and they re-check every request server-side.

/// Whether the role may manage team members and invites (supervisor only).
bool canManageTeam(UserRole? role) => role == UserRole.supervisor;

/// Whether the role may view org-wide reports/statistics (FED-7.2). Coordinators
/// and supervisors oversee the whole org; carers only see their own cases, so
/// org-wide aggregates aren't meaningful (or fully readable) for them.
bool canViewReports(UserRole? role) =>
    role == UserRole.coordinator || role == UserRole.supervisor;

/// Localized display name for a staff role (same pattern as the case labels).
String userRoleLabel(AppLocalizations l10n, UserRole role) => switch (role) {
  UserRole.carer => l10n.userRoleCarer,
  UserRole.coordinator => l10n.userRoleCoordinator,
  UserRole.supervisor => l10n.userRoleSupervisor,
};
