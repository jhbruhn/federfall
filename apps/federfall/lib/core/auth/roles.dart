import 'package:federfall/l10n/gen/app_localizations.dart';
import 'package:federfall_models/federfall_models.dart';

/// Role-derived UI capabilities (FED-3.3).
///
/// These gate what the UI *offers* so users aren't shown actions they can't
/// perform. They are NOT the security boundary — the PocketBase API access
/// rules (FED-1.11) are, and they re-check every request server-side.

/// Whether the role may manage team members and invites (supervisor only).
bool canManageTeam(UserRole? role) => role == UserRole.supervisor;

/// Whether the role may merge duplicate animal records (federfall-eqy6).
/// Mirrors the server `animals` delete rule (1700000010_access_rules.js) — a
/// merge deletes the duplicate, so it needs the same authority.
bool canMergeAnimals(UserRole? role) => role == UserRole.supervisor;

/// Whether the role may hard-delete an animal or a case (federfall-vfl7).
/// Mirrors the server `animals` / `cases` delete rules
/// (1700000010_access_rules.js). Destroying an animal takes its whole case
/// history with it (`cases.animal` cascades since 1700000057), so this is
/// deliberately the narrowest role, separate from `canEditCase` — an active
/// carer may write a case's timeline without being able to erase it.
///
/// Custody (1700000077) adds nothing on top of this and is deliberately not
/// ANDed in at the delete call sites: a supervisor overrides every custody
/// branch, so the two can never disagree here. Where custody DOES narrow a
/// delete is on the animal-scoped records, whose delete rules are author-based
/// rather than supervisor-only — see [weightDeletableBy] / [eggDeletableBy].
bool canDeleteRecords(UserRole? role) => role == UserRole.supervisor;

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

/// Whether a case with [status] still leaves its bird in somebody's care.
///
/// The same set the server rules name (1700000077) and the case browser calls
/// "active" (federfall-jt5u) — named rather than negated so the three answers
/// cannot drift. A null status is a case whose status column is `""`, which the
/// rule counts as open: the create hook defaults to `in_care`, but a row
/// imported through the Admin UI can carry none at all.
bool _caseHoldsBird(CaseStatus? status) =>
    status == null ||
    status == CaseStatus.inCare ||
    status == CaseStatus.readyForRelease;

/// Whether [animal] is housed in an enclosure. Read off the animal rather than
/// off a resolved [Aviary], so a dangling or unreadable enclosure cannot make a
/// resident look like a bird at large.
bool _isHoused(Animal animal) {
  final aviaryId = animal.currentAviary;
  return aviaryId != null && aviaryId.isNotEmpty;
}

/// Whether [me] currently HOLDS [animal], and may therefore write about it —
/// the identity itself (name, species, sex, photo) and its animal-scoped rows
/// (weights, markings, egg records).
///
/// Mirrors the `animals` update rule of 1700000077 and the one-hop-further
/// version 1700000079 puts on `weights` / `markings` / `egg_records`, branch for
/// branch: a coordinator or supervisor overrides everything, the keeper of the
/// bird's enclosure holds it, and so does the active carer of a non-disposed
/// case on it or anyone that case is shared with at `edit`. Reads stay org-wide
/// — re-identification depends on them — so this gates writes only.
///
/// Deliberately NOT keyed on `lifetime_status`: that field is derived from the
/// last disposition and lags on purpose (federfall-sinp), so a resident under
/// treatment still reads `in_aviary` and a re-admitted bird still reads
/// `at_large_released`. The open case and the enclosure relation are live, so
/// this reads those, exactly as the rules do.
///
/// [cases] are the animal's case SUMMARIES, not its `Case` records: the
/// `case_summaries` view is org-wide, and a carer cannot read a teammate's case
/// at all — asking the access-scoped collection would make somebody else's open
/// case invisible here while the server still counts it.
///
/// [aviary] is the resolved enclosure, or null when the bird is at large *or*
/// when its enclosure could not be read; [editSharedCaseIds] are the cases [me]
/// holds an `edit` share on (see `myEditSharedCaseIds`).
bool animalWritableBy(
  Animal animal,
  AppUser? me, {
  required Aviary? aviary,
  required List<CaseSummary> cases,
  required Set<String> editSharedCaseIds,
}) {
  if (me == null) return false;
  if (me.role == UserRole.coordinator || me.role == UserRole.supervisor) {
    return true;
  }
  if (aviary != null && aviary.keeper == me.id) return true;
  return cases.any(
    (c) =>
        _caseHoldsBird(c.status) &&
        (c.activeCarer == me.id || editSharedCaseIds.contains(c.id)),
  );
}

/// Whether [me] may open a NEW case on [animal] — mirrors
/// `lib_custody.js`'s `requireAdmissible()`, the authoritative gate behind
/// `POST /api/federfall/intake` (the app's only case-create path).
///
/// Wider than [animalWritableBy] in one direction and narrower in another. A
/// bird nobody holds — no enclosure, no open case — is anyone's to admit, which
/// is the whole point of re-identifying a returning bird. But a bird recorded
/// as deceased is refused for everyone but a coordinator/supervisor: a new case
/// on one means the death record was wrong, and that is a correction rather
/// than an admission. `lifetime_status` is trustworthy in exactly that way —
/// it lags toward the PAST, so it can read stale-alive but never falsely dead.
bool animalAdmissibleBy(
  Animal animal,
  AppUser? me, {
  required Aviary? aviary,
  required List<CaseSummary> cases,
  required Set<String> editSharedCaseIds,
}) {
  if (me == null) return false;
  if (me.role == UserRole.coordinator || me.role == UserRole.supervisor) {
    return true;
  }
  if (animal.lifetimeStatus == LifetimeStatus.deceased) return false;
  final holds = animalWritableBy(
    animal,
    me,
    aviary: aviary,
    cases: cases,
    editSharedCaseIds: editSharedCaseIds,
  );
  if (holds) return true;
  return !_isHoused(animal) && !cases.any((c) => _caseHoldsBird(c.status));
}

/// Whether [me] may place a bird into [aviary] — its keeper, or a
/// coordinator/supervisor. Mirrors the `animals` CREATE rule of 1700000077,
/// which is what the aviary's "add resident" sheet writes.
///
/// This is where the UI and the server used to disagree in the other direction:
/// the FAB was gated on [canManageAviaries] alone (federfall-ftm2) while the
/// rule now names the keeper too, so an enclosure's own keeper was refused a
/// placement the server accepts.
bool aviaryStockableBy(Aviary aviary, AppUser? me) =>
    me != null && (canManageAviaries(me.role) || aviary.keeper == me.id);

/// Whether [me] may edit [aviary] itself — its keeper, or a
/// coordinator/supervisor. Mirrors 1700000086's update rule.
///
/// The keeper answers for the enclosure, so its capacity, location and notes
/// are theirs to correct. Who the KEEPER is stays a coordinator's to change
/// (naming somebody else hands over custody of every resident and the sponsor
/// details of their patronages) — see [aviaryKeeperReassignableBy], which is
/// what the form's keeper field is gated on.
bool aviaryEditableBy(Aviary aviary, AppUser? me) =>
    aviaryStockableBy(aviary, me);

/// Whether [me] may see an enclosure's flock-care chronology — the Pflege tab:
/// its aviary journal plus the rollup of conditions diagnosed on its residents.
/// Its keeper, or a coordinator/supervisor. Mirrors the aviary branch of the
/// `journal_entries` read rule as 1700000089 leaves it.
///
/// This gates whether the tab is RENDERED AT ALL rather than just its controls,
/// on [sponsorshipsReadableBy]'s reasoning: a flock journal is a care record of
/// named birds under treatment, and an always-present tab that reads empty for
/// everyone but the keeper is a worse answer than no tab.
///
/// Resolution is live, off the enclosure's current [Aviary.keeper] — handing an
/// enclosure over hands over its whole log, exactly as the rule resolves it.
bool aviaryFlockCareVisibleBy(Aviary aviary, AppUser? me) =>
    me != null && (canManageAviaries(me.role) || aviary.keeper == me.id);

/// Whether [me] may write [aviary]'s journal. The same set as
/// [aviaryFlockCareVisibleBy], which is what 1700000089 made it: there is
/// nothing on a flock entry a reader may see but a writer may not add, and the
/// person doing the cleaning is the one who has something to write down.
bool aviaryJournalWritableBy(Aviary aviary, AppUser? me) =>
    aviaryFlockCareVisibleBy(aviary, me);

/// Whether [me] may hand an enclosure to a different keeper — the role that
/// manages enclosures, never the keeper themselves. The other half of
/// 1700000086: the rule lets a keeper send `keeper` only while it still names
/// them, so the form must not offer anyone else.
bool aviaryKeeperReassignableBy(AppUser? me) =>
    me != null && canManageAviaries(me.role);

/// Whether [me] may see the Patenschaften of a bird living in [aviary]
/// (federfall-5s5j). Mirrors 1700000085's read rule: a coordinator or
/// supervisor, or the KEEPER of the enclosure the bird currently lives in.
///
/// Narrower than [animalWritableBy] on purpose, and that is the feature rather
/// than an omission: custody of a bird is not access to its patronage, so the
/// bird's own carer is not a reader. [aviary] is the resolved enclosure, or
/// null when the bird lives in none — in which case no keeper qualifies and
/// only the two roles do, exactly as the rule resolves it.
///
/// This gates whether the section is RENDERED AT ALL, not just its controls.
/// An always-present empty „Patenschaften" card would tell the whole org that
/// this bird has a sponsor, which is a leak with no values in it.
bool sponsorshipsReadableBy(Aviary? aviary, AppUser? me) =>
    me != null &&
    (me.role == UserRole.coordinator ||
        me.role == UserRole.supervisor ||
        (aviary != null && aviary.keeper == me.id));

/// Whether [me] may RECORD a patronage on a bird living in [aviary]. Mirrors
/// `pb_hooks/sponsorships.pb.js`: the enclosure's keeper, or a
/// coordinator/supervisor, and never on a bird that lives in no enclosure.
///
/// Identical to [sponsorshipsReadableBy] except for that last clause, which is
/// why it is a separate predicate: a coord/sup READS the patronages of a bird
/// that has left aviary care (that is who winds them down), but nobody may
/// create one there.
bool sponsorshipWritableBy(Aviary? aviary, AppUser? me) =>
    aviary != null && sponsorshipsReadableBy(aviary, me);

/// Whether [me] may delete [weight]. Mirrors the server delete rule
/// (1700000047): a weight is shared clinical history, so destroying one is
/// reserved for its author (correct-a-typo path) or a supervisor.
///
/// Since 1700000079 (federfall-q7ks.3) that author rule sits on top of CUSTODY
/// rather than of org-wide access: recording, editing and deleting all require
/// holding the bird, so an author who no longer does cannot delete either.
/// This predicate therefore answers only "is the author guard satisfied" —
/// combine it with the custody check before offering the control.
bool weightDeletableBy(Weight weight, AppUser? me) =>
    me != null &&
    (me.role == UserRole.supervisor ||
        (weight.author != null && weight.author == me.id));

/// Whether [me] may delete [egg]. Mirrors the server delete rule
/// (1700000056, which copies 1700000047's stance for weights): a laying record
/// is shared history of the animal, so destroying one is reserved for its
/// author or a supervisor.
///
/// As with [weightDeletableBy], since 1700000079 logging, editing,
/// re-attributing and deleting all require CUSTODY of the bird — this answers
/// the author half only.
bool eggDeletableBy(EggRecord egg, AppUser? me) =>
    me != null &&
    (me.role == UserRole.supervisor ||
        (egg.author != null && egg.author == me.id));

/// Whether [me] may delete [vaccination]. Mirrors the server delete rule
/// (1700000087, the same author-or-supervisor stance as weights and eggs): a
/// vaccination is shared history of the animal, and a batch number is the kind
/// of fact somebody may need years later, so destroying one is reserved.
///
/// As with [weightDeletableBy], recording, editing and deleting all require
/// CUSTODY of the bird — this answers the author half only.
bool vaccinationDeletableBy(Vaccination vaccination, AppUser? me) =>
    me != null &&
    (me.role == UserRole.supervisor ||
        (vaccination.author != null && vaccination.author == me.id));

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
