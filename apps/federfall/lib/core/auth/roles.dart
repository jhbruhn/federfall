import 'package:federfall/l10n/gen/app_localizations.dart';
import 'package:federfall_models/federfall_models.dart';

/// Role-derived UI capabilities (FED-3.3).
///
/// These gate what the UI *offers* so users aren't shown actions they can't
/// perform. They are NOT the security boundary — the PocketBase API access
/// rules (FED-1.11) are, and they re-check every request server-side.

/// Whether the role may manage team members and invites (supervisor only).
bool canManageTeam(UserRole? role) => role == UserRole.supervisor;

/// Whether [me] may write to [medicalCase] — edit the case itself and
/// create/edit/delete its child records (timeline entries, etc.). Mirrors the
/// server `caseEdit` / `childEdit` access rules (1700000010_access_rules.js):
/// the active carer, a supervisor, or anyone the case is shared with at `edit`
/// access. Coordinators can view but not edit. [shares] are the case's shares
/// (empty is fine — only the share branch needs them). Drives both whether the
/// UI offers write controls and the read-only badge.
bool caseEditableBy(Case medicalCase, AppUser? me, List<CaseShare> shares) {
  if (me == null) return false;
  if (me.role == UserRole.supervisor) return true;
  if (medicalCase.activeCarer == me.id) return true;
  return shares.any(
    (s) => s.sharedWith == me.id && s.access == ShareAccess.edit,
  );
}

/// Whether the role may view org-wide reports/statistics (FED-7.2). Coordinators
/// and supervisors oversee the whole org; carers only see their own cases, so
/// org-wide aggregates aren't meaningful (or fully readable) for them.
bool canViewReports(UserRole? role) =>
    role == UserRole.coordinator || role == UserRole.supervisor;

/// Whether the role may create/edit aviaries (FED-6.1). All members can view
/// them; coordinators and supervisors manage them (delete is supervisor-only,
/// enforced server-side).
bool canManageAviaries(UserRole? role) =>
    role == UserRole.coordinator || role == UserRole.supervisor;

/// Whether [role] is a not-yet-provisioned guest (self-registered via OAuth2,
/// awaiting a supervisor's promotion). Such users are routed to the pending
/// screen rather than the app shell, and walled off server-side regardless.
bool isGuest(UserRole? role) => role == UserRole.guest;

/// Localized display name for a staff role (same pattern as the case labels).
String userRoleLabel(AppLocalizations l10n, UserRole role) => switch (role) {
  UserRole.carer => l10n.userRoleCarer,
  UserRole.coordinator => l10n.userRoleCoordinator,
  UserRole.supervisor => l10n.userRoleSupervisor,
  UserRole.guest => l10n.userRoleGuest,
};
