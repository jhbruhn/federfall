import 'package:federfall/core/auth/roles.dart';
import 'package:federfall/features/cases/cases_labels.dart';
import 'package:federfall/l10n/gen/app_localizations.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Turns an [AuditEvent] into something a screen can lay out.
///
/// The renderer returns STRUCTURE, not a finished sentence: a title, an
/// optional subtitle and a list of labelled facts. A sentence would have to be
/// reassembled for every layout (a dense list row, a wide two-pane detail, a
/// per-case section) and would fight German word order at every turn.
///
/// Three rules hold throughout, and they are what keep the log honest:
///
///  1. The envelope alone always renders. Every lookup here falls back to the
///     raw wire value rather than to a blank, so a server that logs an action
///     this build has never heard of shows "Unknown action (x.y)" plus who did
///     it and to what — never an empty row.
///  2. Values are shown as the wire strings turned back into labels, never as
///     raw enum names. `CaseStatus.fromWire(change.to)` is exactly what the
///     `wire` convention on every domain enum is for.
///  3. A redacted change says that the field changed and stops there. It has no
///     value to show, and inventing a placeholder that looked like one would be
///     worse than saying so.

/// One labelled piece of context under an audit line.
@immutable
class AuditFact {
  const AuditFact(this.label, this.value);

  final String label;
  final String value;

  @override
  bool operator ==(Object other) =>
      other is AuditFact && other.label == label && other.value == value;

  @override
  int get hashCode => Object.hash(label, value);
}

/// A renderable audit entry.
@immutable
class AuditLine {
  const AuditLine({
    required this.title,
    required this.icon,
    this.subtitle,
    this.facts = const [],
  });

  /// What happened, e.g. „Fall übergeben".
  final String title;

  /// What it happened to — the subject label, or the case number.
  final String? subtitle;

  /// Labelled context: who it went to, which format, how many findings.
  final List<AuditFact> facts;

  final IconData icon;
}

/// The translated name of [action], or a self-describing fallback naming the
/// raw wire value so an unknown action is still legible.
String auditActionTitle(
  AppLocalizations l10n,
  AuditAction? action,
  String rawAction,
) => switch (action) {
  AuditAction.caseIntake => l10n.auditActionCaseIntake,
  AuditAction.caseCreated => l10n.auditActionCaseCreated,
  AuditAction.caseUpdated => l10n.auditActionCaseUpdated,
  AuditAction.caseDeleted => l10n.auditActionCaseDeleted,
  AuditAction.caseHandoff => l10n.auditActionCaseHandoff,
  AuditAction.caseShared => l10n.auditActionCaseShared,
  AuditAction.caseShareRevoked => l10n.auditActionCaseShareRevoked,
  AuditAction.animalCreated => l10n.auditActionAnimalCreated,
  AuditAction.animalUpdated => l10n.auditActionAnimalUpdated,
  AuditAction.animalDeleted => l10n.auditActionAnimalDeleted,
  AuditAction.animalMerged => l10n.auditActionAnimalMerged,
  AuditAction.weightCreated => l10n.auditActionWeightCreated,
  AuditAction.weightUpdated => l10n.auditActionWeightUpdated,
  AuditAction.weightDeleted => l10n.auditActionWeightDeleted,
  AuditAction.markingCreated => l10n.auditActionMarkingCreated,
  AuditAction.markingUpdated => l10n.auditActionMarkingUpdated,
  AuditAction.markingDeleted => l10n.auditActionMarkingDeleted,
  AuditAction.conditionAdded => l10n.auditActionConditionAdded,
  AuditAction.conditionUpdated => l10n.auditActionConditionUpdated,
  AuditAction.conditionRemoved => l10n.auditActionConditionRemoved,
  AuditAction.medicationPrescribed => l10n.auditActionMedicationPrescribed,
  AuditAction.medicationUpdated => l10n.auditActionMedicationUpdated,
  AuditAction.medicationDeleted => l10n.auditActionMedicationDeleted,
  AuditAction.administrationLogged => l10n.auditActionAdministrationLogged,
  AuditAction.administrationUpdated => l10n.auditActionAdministrationUpdated,
  AuditAction.administrationDeleted => l10n.auditActionAdministrationDeleted,
  AuditAction.journalCreated => l10n.auditActionJournalCreated,
  AuditAction.journalUpdated => l10n.auditActionJournalUpdated,
  AuditAction.journalDeleted => l10n.auditActionJournalDeleted,
  AuditAction.placementCreated => l10n.auditActionPlacementCreated,
  AuditAction.placementUpdated => l10n.auditActionPlacementUpdated,
  AuditAction.placementDeleted => l10n.auditActionPlacementDeleted,
  AuditAction.dispositionCreated => l10n.auditActionDispositionCreated,
  AuditAction.dispositionUpdated => l10n.auditActionDispositionUpdated,
  AuditAction.dispositionDeleted => l10n.auditActionDispositionDeleted,
  AuditAction.examSaved => l10n.auditActionExamSaved,
  AuditAction.examDeleted => l10n.auditActionExamDeleted,
  AuditAction.examFindingCreated => l10n.auditActionExamFindingCreated,
  AuditAction.examFindingUpdated => l10n.auditActionExamFindingUpdated,
  AuditAction.examFindingDeleted => l10n.auditActionExamFindingDeleted,
  AuditAction.microscopySaved => l10n.auditActionMicroscopySaved,
  AuditAction.microscopyDeleted => l10n.auditActionMicroscopyDeleted,
  AuditAction.microscopyFindingCreated =>
    l10n.auditActionMicroscopyFindingCreated,
  AuditAction.microscopyFindingUpdated =>
    l10n.auditActionMicroscopyFindingUpdated,
  AuditAction.microscopyFindingDeleted =>
    l10n.auditActionMicroscopyFindingDeleted,
  AuditAction.eggRecordCreated => l10n.auditActionEggRecordCreated,
  AuditAction.eggRecordUpdated => l10n.auditActionEggRecordUpdated,
  AuditAction.eggRecordDeleted => l10n.auditActionEggRecordDeleted,
  AuditAction.followUpCreated => l10n.auditActionFollowUpCreated,
  AuditAction.followUpUpdated => l10n.auditActionFollowUpUpdated,
  AuditAction.followUpDeleted => l10n.auditActionFollowUpDeleted,
  AuditAction.vetAppointmentCreated => l10n.auditActionVetAppointmentCreated,
  AuditAction.vetAppointmentUpdated => l10n.auditActionVetAppointmentUpdated,
  AuditAction.vetAppointmentDeleted => l10n.auditActionVetAppointmentDeleted,
  AuditAction.quarantineSet => l10n.auditActionQuarantineSet,
  AuditAction.quarantineUpdated => l10n.auditActionQuarantineUpdated,
  AuditAction.quarantineCleared => l10n.auditActionQuarantineCleared,
  AuditAction.aviaryCreated => l10n.auditActionAviaryCreated,
  AuditAction.aviaryUpdated => l10n.auditActionAviaryUpdated,
  AuditAction.aviaryDeleted => l10n.auditActionAviaryDeleted,
  AuditAction.finderCreated => l10n.auditActionFinderCreated,
  AuditAction.finderUpdated => l10n.auditActionFinderUpdated,
  AuditAction.finderDeleted => l10n.auditActionFinderDeleted,
  AuditAction.finderPiiPurged => l10n.auditActionFinderPiiPurged,
  AuditAction.finderOrphanDeleted => l10n.auditActionFinderOrphanDeleted,
  AuditAction.userInvited => l10n.auditActionUserInvited,
  AuditAction.userUpdated => l10n.auditActionUserUpdated,
  AuditAction.userRoleChanged => l10n.auditActionUserRoleChanged,
  AuditAction.userDeactivated => l10n.auditActionUserDeactivated,
  AuditAction.userReactivated => l10n.auditActionUserReactivated,
  AuditAction.userDeleted => l10n.auditActionUserDeleted,
  AuditAction.orgSettingsUpdated => l10n.auditActionOrgSettingsUpdated,
  AuditAction.codeListCreated => l10n.auditActionCodeListCreated,
  AuditAction.codeListUpdated => l10n.auditActionCodeListUpdated,
  AuditAction.codeListDeleted => l10n.auditActionCodeListDeleted,
  AuditAction.authLogin => l10n.auditActionAuthLogin,
  AuditAction.authOauth2Login => l10n.auditActionAuthOauth2Login,
  AuditAction.authLoginFailed => l10n.auditActionAuthLoginFailed,
  AuditAction.authPasswordReset => l10n.auditActionAuthPasswordReset,
  AuditAction.authPasswordChanged => l10n.auditActionAuthPasswordChanged,
  AuditAction.authMfaEnabled => l10n.auditActionAuthMfaEnabled,
  AuditAction.authMfaDisabled => l10n.auditActionAuthMfaDisabled,
  AuditAction.reportExported => l10n.auditActionReportExported,
  AuditAction.caseReportPrinted => l10n.auditActionCaseReportPrinted,
  AuditAction.oauth2UserProvisioned => l10n.auditActionOauth2UserProvisioned,
  AuditAction.supervisorBootstrapped => l10n.auditActionSupervisorBootstrapped,
  AuditAction.auditPurged => l10n.auditActionAuditPurged,
  null => l10n.auditActionUnknown(rawAction),
};

/// How to name whoever did it.
///
/// Three states, and the difference matters: a person, a machine, or a person
/// whose account is gone. The snapshot label is what makes the third possible
/// at all — the log stores the name, not a relation, precisely so a deleted
/// member does not turn every one of their actions into a blank.
String auditActorName(AppLocalizations l10n, AuditEvent e) {
  switch (e.actorKind) {
    case AuditActorKind.system:
      return l10n.auditActorSystem;
    case AuditActorKind.cron:
      return l10n.auditActorCron;
    case AuditActorKind.superuser:
      return e.actorLabel.isEmpty ? l10n.auditActorSuperuser : e.actorLabel;
    case AuditActorKind.user:
      if (e.actorLabel.isEmpty) return l10n.auditActorUnknown;
      return e.actorLabel;
  }
}

/// What a supervisor is looking through the log FOR.
///
/// Not the action's own domain: there are 27 of those and „exam_finding" is not
/// a question anybody arrives with. These are areas of work, each mapping to an
/// explicit list of actions the existing `AuditQuery.actions` filter already
/// takes. Every action belongs to exactly one topic, and the label test fails
/// the build on one that belongs to none or two — otherwise a new action would
/// silently be unreachable by filter.
enum AuditTopic {
  cases,
  treatment,
  housing,
  access,
  signIn,
  exports;

  /// The actions this topic covers.
  List<AuditAction> get actions =>
      AuditAction.values.where((a) => a.topic == this).toList();
}

extension AuditActionTopic on AuditAction {
  /// Which area of work this action belongs to.
  AuditTopic get topic => switch (this) {
    AuditAction.caseIntake ||
    AuditAction.caseCreated ||
    AuditAction.caseUpdated ||
    AuditAction.caseDeleted ||
    AuditAction.animalCreated ||
    AuditAction.animalUpdated ||
    AuditAction.animalDeleted ||
    AuditAction.animalMerged ||
    AuditAction.finderCreated ||
    AuditAction.finderUpdated ||
    AuditAction.finderDeleted ||
    AuditAction.finderPiiPurged ||
    AuditAction.finderOrphanDeleted => AuditTopic.cases,

    AuditAction.weightCreated ||
    AuditAction.weightUpdated ||
    AuditAction.weightDeleted ||
    AuditAction.markingCreated ||
    AuditAction.markingUpdated ||
    AuditAction.markingDeleted ||
    AuditAction.conditionAdded ||
    AuditAction.conditionUpdated ||
    AuditAction.conditionRemoved ||
    AuditAction.medicationPrescribed ||
    AuditAction.medicationUpdated ||
    AuditAction.medicationDeleted ||
    AuditAction.administrationLogged ||
    AuditAction.administrationUpdated ||
    AuditAction.administrationDeleted ||
    AuditAction.journalCreated ||
    AuditAction.journalUpdated ||
    AuditAction.journalDeleted ||
    AuditAction.examSaved ||
    AuditAction.examDeleted ||
    AuditAction.examFindingCreated ||
    AuditAction.examFindingUpdated ||
    AuditAction.examFindingDeleted ||
    AuditAction.microscopySaved ||
    AuditAction.microscopyDeleted ||
    AuditAction.microscopyFindingCreated ||
    AuditAction.microscopyFindingUpdated ||
    AuditAction.microscopyFindingDeleted ||
    AuditAction.eggRecordCreated ||
    AuditAction.eggRecordUpdated ||
    AuditAction.eggRecordDeleted ||
    AuditAction.followUpCreated ||
    AuditAction.followUpUpdated ||
    AuditAction.followUpDeleted ||
    AuditAction.vetAppointmentCreated ||
    AuditAction.vetAppointmentUpdated ||
    AuditAction.vetAppointmentDeleted ||
    AuditAction.quarantineSet ||
    AuditAction.quarantineUpdated ||
    AuditAction.quarantineCleared ||
    AuditAction.dispositionCreated ||
    AuditAction.dispositionUpdated ||
    AuditAction.dispositionDeleted => AuditTopic.treatment,

    AuditAction.caseHandoff ||
    AuditAction.placementCreated ||
    AuditAction.placementUpdated ||
    AuditAction.placementDeleted ||
    AuditAction.aviaryCreated ||
    AuditAction.aviaryUpdated ||
    AuditAction.aviaryDeleted => AuditTopic.housing,

    AuditAction.caseShared ||
    AuditAction.caseShareRevoked ||
    AuditAction.userInvited ||
    AuditAction.userUpdated ||
    AuditAction.userRoleChanged ||
    AuditAction.userDeactivated ||
    AuditAction.userReactivated ||
    AuditAction.userDeleted ||
    AuditAction.orgSettingsUpdated ||
    AuditAction.codeListCreated ||
    AuditAction.codeListUpdated ||
    AuditAction.codeListDeleted ||
    AuditAction.oauth2UserProvisioned ||
    AuditAction.supervisorBootstrapped ||
    AuditAction.auditPurged => AuditTopic.access,

    AuditAction.authLogin ||
    AuditAction.authOauth2Login ||
    AuditAction.authLoginFailed ||
    AuditAction.authPasswordReset ||
    AuditAction.authPasswordChanged ||
    AuditAction.authMfaEnabled ||
    AuditAction.authMfaDisabled => AuditTopic.signIn,

    AuditAction.reportExported ||
    AuditAction.caseReportPrinted => AuditTopic.exports,
  };
}

/// The topic name, for the filter chip.
String auditTopicLabel(AppLocalizations l10n, AuditTopic t) => switch (t) {
  AuditTopic.cases => l10n.auditTopicCases,
  AuditTopic.treatment => l10n.auditTopicTreatment,
  AuditTopic.housing => l10n.auditTopicHousing,
  AuditTopic.access => l10n.auditTopicAccess,
  AuditTopic.signIn => l10n.auditTopicSignIn,
  AuditTopic.exports => l10n.auditTopicExports,
};

/// The severity name, for the filter chips.
String auditSeverityLabel(AppLocalizations l10n, AuditSeverity s) =>
    switch (s) {
      AuditSeverity.info => l10n.auditSeverityInfo,
      AuditSeverity.notice => l10n.auditSeverityNotice,
      AuditSeverity.security => l10n.auditSeveritySecurity,
    };

/// A human name for a changed field.
///
/// Falls back to the raw column name rather than hiding the change: „status →
/// disposed" for a field nobody has translated yet is worse than nothing only
/// if it is missing entirely. Every field in the server's own CONTENT_FIELDS
/// allowlist is expected to be named here, and
/// `audit_labels_test.dart` fails the build on one that is not.
String auditFieldLabel(AppLocalizations l10n, String collection, String field) {
  // (collection, field) wins, because the same column name means different
  // things in different collections and guessing wrong is worse than not
  // translating at all: `type` is the outcome of a case on a disposition and
  // the kind of ring on a marking (federfall-ybua.3).
  final perCollection = switch ((collection, field)) {
    ('markings', 'type') => l10n.markingFieldType,
    ('dispositions', 'type') => l10n.auditFieldType,
    _ => null,
  };
  if (perCollection != null) return perCollection;

  return switch (field) {
    'status' => l10n.caseStatusFieldLabel,
    'active_carer' => l10n.auditFieldActiveCarer,
    'weight_g' => l10n.weightFieldGrams,
    'notes' => l10n.aviaryFieldNotes,
    'name' => l10n.aviaryFieldName,
    'species' => l10n.casesSpeciesLabel,
    'sex' => l10n.caseFieldSex,
    'age_class' => l10n.caseFieldAgeClass,
    'lifetime_status' => l10n.auditFieldLifetimeStatus,
    'current_aviary' => l10n.aviaryDetailTitle,
    'role' => l10n.auditFactRole,
    'is_active' => l10n.memberActiveLabel,
    'password' => l10n.authPasswordLabel,
    'type' => l10n.auditFieldType,
    'count' => l10n.auditFieldCount,
    'dose' || 'dose_rate' => l10n.auditFieldDose,
    'frequency_kind' => l10n.auditFieldFrequency,
    'interval_hours' => l10n.auditFieldIntervalHours,
    'measured_at' => l10n.auditFieldMeasuredAt,
    'administered_at' => l10n.auditFieldAdministeredAt,
    'disposed_at' => l10n.auditFieldDisposedAt,
    'due_at' => l10n.auditFieldDueAt,
    'done_at' => l10n.auditFieldDoneAt,
    'starts_at' => l10n.auditFieldStartsAt,
    'admitted_at' => l10n.auditFieldAdmittedAt,
    'quarantine_until' => l10n.auditFieldQuarantineUntil,
    'capacity' => l10n.auditFieldCapacity,
    'access' => l10n.auditFieldAccess,
    'label' => l10n.auditFieldLabel,
    'certainty' => l10n.auditFieldCertainty,
    'examined_at' => l10n.examDateLabel,
    'hydration' => l10n.examHydrationLabel,
    'mentation' => l10n.examMentationLabel,
    'dose_unit' => l10n.medUnit,
    // The rest of the server's content allowlist (federfall-ybua.4), each
    // reusing the key the app already names that field by elsewhere so the log
    // and the screen that owns the field agree on what it is called.
    'applied_at' => l10n.markingFieldApplied,
    'present_at_find' => l10n.markingFieldPresentAtFind,
    'removed_at' => l10n.auditFieldRemovedAt,
    'onset_date' => l10n.conditionFieldOnset,
    'resolved_date' => l10n.conditionFieldResolved,
    'started_at' => l10n.medStarted,
    'ended_at' => l10n.medEnded,
    'moved_in_at' => l10n.placementFieldMovedAt,
    'where_holding' => l10n.auditFieldWhereHolding,
    'release_type' => l10n.dispositionFieldReleaseType,
    'transfer_type' => l10n.dispositionFieldTransferType,
    'body_condition' => l10n.examBodyConditionLabel,
    'system' => l10n.auditFieldBodySystem,
    'laid_at' => l10n.eggFieldDate,
    'fate' => l10n.eggFieldFate,
    'attended_at' => l10n.auditFieldAttendedAt,
    'cancelled_at' => l10n.auditFieldCancelledAt,
    'set_at' => l10n.auditFieldSetAt,
    'active' => l10n.aviaryFieldActive,
    // ── microscopy ─────────────────────────────────────────────────────────
    'sample_type' => l10n.microscopyFieldSampleType,
    'method' => l10n.microscopyFieldMethod,
    'examined_by' => l10n.microscopyFieldExaminedBy,
    'external_lab' => l10n.microscopyFieldExternalLab,
    'no_findings' => l10n.microscopyFieldNoFindings,
    'severity' => l10n.microscopyFieldSeverity,
    'finding_type' => l10n.microscopyFieldFindingType,
    'sample' => l10n.microscopyFieldSample,
    // Which probe kinds a vocabulary entry is offered for.
    'sample_types' => l10n.microscopyFieldSampleTypes,
    // Everything else an UPDATE can surface (federfall-g5ap). CONTENT_FIELDS
    // above is the create/delete allowlist; a diff has no allowlist, so any
    // column of an audited collection can arrive here — and did, as its raw
    // SQLite name. test_rules.py asks the live schema and fails the build on
    // one that is missing, which is why this list is exhaustive rather than
    // whatever anybody happened to notice.
    //
    // ── who did what to the record ─────────────────────────────────────────
    'admitted_by' => l10n.auditFieldAdmittedBy,
    'transported_by' => l10n.auditFieldTransportedBy,
    'administered_by' => l10n.auditFieldAdministeredBy,
    'applied_by' => l10n.auditFieldAppliedBy,
    'prescribed_by' => l10n.auditFieldPrescribedBy,
    'performed_by' => l10n.auditFieldPerformedBy,
    'examiner' => l10n.auditFieldExaminer,
    'created_by' => l10n.auditFieldCreatedBy,
    'author' => l10n.auditFieldAuthor,
    'set_by' => l10n.auditFieldSetBy,
    'invited_by' => l10n.auditFieldInvitedBy,
    'shared_by' => l10n.auditFieldSharedBy,
    'shared_with' => l10n.auditFactSharedWith,
    'to_user' => l10n.auditFactHandoffTo,
    'from_user' => l10n.auditFactHandoffFrom,
    'carer' => l10n.placementFieldCarer,
    'keeper' => l10n.aviaryFieldKeeper,
    // ── what it points at ──────────────────────────────────────────────────
    'org' => l10n.auditFieldOrg,
    'case' => l10n.auditFactCase,
    'case_number' => l10n.caseNumberLabel,
    'animal' => l10n.animalDetailTitle,
    'aviary' => l10n.aviaryDetailTitle,
    'condition' => l10n.conditionFieldName,
    'medication' => l10n.auditFieldMedication,
    'exam' => l10n.auditFieldExam,
    'route' => l10n.medRoute,
    'drug' => l10n.medDrug,
    'vet' => l10n.vetAppointmentVetLabel,
    'finder' => l10n.auditFieldFinder,
    'admission_reasons' => l10n.caseReasonsFieldLabel,
    'applied_in_case' => l10n.auditFieldAppliedInCase,
    // ── the case as it was found and admitted ──────────────────────────────
    'found_at' => l10n.caseFieldFoundAt,
    'find_location' => l10n.caseFieldFindLocation,
    'find_geo' => l10n.auditFieldFindGeo,
    'city' => l10n.finderFieldCity,
    'region' => l10n.auditFieldRegion,
    'intake_notes' => l10n.caseFieldIntakeNotes,
    'intake_weight_g' => l10n.auditFieldIntakeWeight,
    'intake_photos' || 'photos' => l10n.caseSectionPhotos,
    'photo' => l10n.animalMergePhotoLabel,
    'attachments' => l10n.auditFieldAttachments,
    'is_releasable' => l10n.auditFieldIsReleasable,
    'is_owned' => l10n.auditFieldIsOwned,
    'tags' => l10n.auditFieldTags,
    // ── the clinical record ────────────────────────────────────────────────
    'text' => l10n.auditFieldText,
    'note' => l10n.examFindingNoteLabel,
    'entry_at' => l10n.auditFieldEntryAt,
    'free_text' => l10n.auditFieldFreeText,
    'reason' => l10n.vetAppointmentReasonLabel,
    'outcome' => l10n.vetAppointmentOutcomeLabel,
    'instructions' => l10n.medInstructions,
    'temperature' => l10n.examTemperatureLabel,
    'mm_color' => l10n.examMmColorLabel,
    'mm_texture' => l10n.examMmTextureLabel,
    'fertility' => l10n.eggFieldFertility,
    'attribution' => l10n.auditFieldAttribution,
    'is_notifiable' => l10n.conditionNotifiableLabel,
    'is_contagious' => l10n.conditionContagiousLabel,
    'is_controlled' => l10n.medControlled,
    'concentration_per_ml' => l10n.auditFieldConcentration,
    'rate_min' => l10n.auditFieldRateMin,
    'rate_max' => l10n.auditFieldRateMax,
    'volume_ml' => l10n.auditFieldVolumeMl,
    'weight_g_used' => l10n.auditFieldWeightUsed,
    // ── where the bird went, and where it lives ────────────────────────────
    'area' => l10n.auditFieldArea,
    'enclosure' => l10n.placementFieldEnclosure,
    'location' => l10n.aviaryFieldLocation,
    'location_geo' => l10n.auditFieldLocationGeo,
    'condition_at_handoff' => l10n.placementFieldCondition,
    'comments' => l10n.placementFieldComments,
    'release_location' => l10n.dispositionFieldReleaseLocation,
    'release_geo' => l10n.auditFieldReleaseGeo,
    'transfer_destination' => l10n.auditFieldTransferDestination,
    'vet_signed_off' => l10n.dispositionVetSignedOff,
    'code' => l10n.markingFieldCode,
    'colour' => l10n.markingFieldColour,
    'scheme_org' => l10n.markingFieldScheme,
    'removed_reason' => l10n.auditFieldRemovedReason,
    // ── people, the organisation, and the finder's own record ──────────────
    'email' => l10n.authEmailLabel,
    'phone' => l10n.finderFieldPhone,
    'alt_phone' => l10n.auditFieldAltPhone,
    'first_name' => l10n.finderFieldFirstName,
    'last_name' => l10n.finderFieldLastName,
    'organisation' => l10n.auditFieldFinderOrganisation,
    'address' => l10n.auditFieldAddress,
    'postal_code' => l10n.auditFieldPostalCode,
    'pii_purged' => l10n.auditFieldPiiPurged,
    'avatar' => l10n.auditFieldAvatar,
    'mfa_enabled' => l10n.profileMfaTitle,
    'contact_email' => l10n.orgContactEmailLabel,
    'contact_phone' => l10n.orgContactPhoneLabel,
    'settings' => l10n.orgSettingsTitle,
    'description' => l10n.auditFieldDescription,
    'reminder_lead_minutes' => l10n.appointmentReminderLeadTitle,
    'reminder_muted' => l10n.auditFieldReminderMuted,
    _ => field,
  };
}

/// A wire value turned back into what the rest of the app calls it.
///
/// This is the payoff of every domain enum carrying its `wire` string: the log
/// stores `"in_care"` and the reader sees „In Pflege", in the same words the
/// case screen uses, without the log having had to store a translation that
/// would then be frozen in whatever language the actor happened to use.
String auditValueLabel(
  AppLocalizations l10n,
  String collection,
  String field,
  String? wire,
) {
  if (wire == null || wire.isEmpty) return l10n.auditValueEmpty;
  // Collection-specific first, for the same reason as auditFieldLabel: a shared
  // column name is not a shared enum. `status` resolved through CaseStatus
  // everywhere left an exam finding reading „abnormal", in English, next to a
  // findingStatusLabel that has said „Auffällig" all along (federfall-ybua.3).
  if (collection == 'exam_findings' && field == 'status') {
    final v = FindingStatus.fromWire(wire);
    return v == null ? wire : findingStatusLabel(l10n, v);
  }
  // Each arm resolves the wire value through the same enum the rest of the app
  // uses, and falls back to the stored string when it does not resolve — an
  // enum value this build predates should still be visible, not blank. A
  // relation's value is an id and resolves through none of them; it is the
  // server's snapshotted label that renders it, see [auditChangeSide].
  switch (field) {
    case 'status':
      final v = CaseStatus.fromWire(wire);
      return v == null ? wire : caseStatusLabel(l10n, v);
    case 'lifetime_status':
      final v = LifetimeStatus.fromWire(wire);
      return v == null ? wire : lifetimeStatusLabel(l10n, v);
    case 'sex':
      final v = Sex.fromWire(wire);
      return v == null ? wire : sexLabel(l10n, v);
    case 'age_class':
      final v = AgeClass.fromWire(wire);
      return v == null ? wire : ageClassLabel(l10n, v);
    case 'role':
      final v = UserRole.fromWire(wire);
      return v == null ? wire : userRoleLabel(l10n, v);
    case 'access':
      final v = ShareAccess.fromWire(wire);
      return v == null ? wire : shareAccessLabel(l10n, v);
    case 'is_active':
    case 'active':
      return wire == 'true' ? l10n.memberActiveLabel : l10n.memberInactive;
    // The outcome of a case — the single most consequential value this log
    // records, and the reason `type` is stored as a wire string rather than as
    // a label: the server has no business deciding which language it is read
    // in (federfall-9k2g).
    case 'type':
      final v = DispositionType.fromWire(wire);
      return v == null ? wire : dispositionTypeLabel(l10n, v);
    case 'certainty':
      final v = Certainty.fromWire(wire);
      return v == null ? wire : certaintyLabel(l10n, v);
    case 'frequency_kind':
      final v = MedicationFrequencyKind.fromWire(wire);
      // The interval belongs to a sibling field; the log records them
      // separately, so this names the kind alone.
      return v == null ? wire : medicationFrequencyLabel(l10n, v, null);
    case 'fate':
      final v = EggFate.fromWire(wire);
      return v == null ? wire : eggFateLabel(l10n, v);
    case 'hydration':
      final v = Hydration.fromWire(wire);
      return v == null ? wire : hydrationLabel(l10n, v);
    case 'mentation':
      final v = Mentation.fromWire(wire);
      return v == null ? wire : mentationLabel(l10n, v);
    case 'system':
      final v = BodySystem.fromWire(wire);
      return v == null ? wire : bodySystemLabel(l10n, v);
    case 'sample_type':
      final v = MicroscopySampleType.fromWire(wire);
      return v == null ? wire : microscopySampleTypeLabel(l10n, v);
    // `method` is only ever a microscopy preparation today; the arm above for
    // a shared column name is where it moves if another collection takes it.
    case 'method':
      final v = MicroscopyMethod.fromWire(wire);
      return v == null ? wire : microscopyMethodLabel(l10n, v);
    case 'examined_by':
      final v = MicroscopyExaminedBy.fromWire(wire);
      return v == null ? wire : microscopyExaminedByLabel(l10n, v);
    case 'severity':
      final v = MicroscopySeverity.fromWire(wire);
      return v == null ? wire : microscopySeverityLabel(v);
    default:
      // A timestamp is stored as PocketBase writes it. Shown raw it is the
      // ugliest thing on the screen and the least readable, so the schema's
      // own naming convention (_at / _date) is enough to know to format it.
      if (field.endsWith('_at') || field.endsWith('_date')) {
        final parsed = DateTime.tryParse(wire.replaceFirst(' ', 'T'));
        if (parsed != null) {
          return DateFormat.yMd(
            l10n.localeName,
          ).add_Hm().format(parsed.toLocal());
        }
      }
      return wire;
  }
}

/// One side of [change], ready to show.
///
/// A relation's stored value is a record id, which reads as noise; the server
/// snapshots what the target was CALLED beside it (federfall-ybua.2), and that
/// label is already human text — running it back through the enum and date
/// resolution below would be wrong. So the label wins where there is one, and
/// the stored value is resolved where there is not, which is also what every
/// row written before the labels existed still gets.
String auditChangeSide(
  AppLocalizations l10n,
  String collection,
  AuditFieldChange change, {
  required bool newValue,
}) {
  final label = newValue ? change.toLabel : change.fromLabel;
  if (label != null && label.isNotEmpty) return label;
  return auditValueLabel(
    l10n,
    collection,
    change.field,
    newValue ? change.to : change.from,
  );
}

/// One line describing a single field change.
String auditChangeText(
  AppLocalizations l10n,
  String collection,
  AuditFieldChange change,
) {
  if (change.redacted) return l10n.auditChangeRedacted;
  final from = change.fromDisplay;
  final to = change.toDisplay;
  final hasFrom = from != null && from.isNotEmpty;
  final hasTo = to != null && to.isNotEmpty;
  final fromLabel = auditChangeSide(l10n, collection, change, newValue: false);
  final toLabel = auditChangeSide(l10n, collection, change, newValue: true);
  if (!hasFrom && hasTo) return l10n.auditChangeSet(toLabel);
  if (hasFrom && !hasTo) return l10n.auditChangeCleared(fromLabel);
  return l10n.auditChangeArrow(fromLabel, toLabel);
}

/// The icon for an event, chosen by what it is about rather than by exact
/// action, so an unrecognised action in a known family still looks right.
IconData auditIcon(AuditEvent e) {
  if (e.severity == AuditSeverity.security) return Icons.shield_outlined;
  final domain = e.rawAction.split('.').first;
  return switch (domain) {
    'case' => Icons.folder_outlined,
    'animal' => Icons.flutter_dash,
    'weight' => Icons.monitor_weight_outlined,
    'marking' => Icons.sell_outlined,
    'condition' => Icons.coronavirus_outlined,
    'medication' || 'administration' => Icons.medication_outlined,
    'journal' => Icons.edit_note,
    'placement' => Icons.swap_horiz,
    'disposition' => Icons.flight_takeoff,
    'exam' || 'exam_finding' => Icons.medical_services_outlined,
    'microscopy' || 'microscopy_finding' => Icons.biotech_outlined,
    'egg_record' => Icons.egg_outlined,
    'follow_up' => Icons.event_repeat,
    'vet_appointment' => Icons.local_hospital_outlined,
    'quarantine' => Icons.do_not_touch_outlined,
    'aviary' => Icons.home_work_outlined,
    'finder' => Icons.person_pin_circle_outlined,
    'user' || 'oauth2' || 'supervisor' => Icons.badge_outlined,
    'org' || 'code_list' => Icons.settings_outlined,
    'auth' => Icons.login,
    'report' || 'case_report' => Icons.description_outlined,
    'audit' => Icons.delete_sweep_outlined,
    _ => Icons.circle_outlined,
  };
}

/// The snapshotted [label] if the server recorded one, else the bare [id].
///
/// Every id in a detail payload is paired with the name it had at the time. The
/// fallback exists for rows written before that was true, where an id nobody
/// can interpret is still better than a blank.
String? _named(String? label, String? id) =>
    (label != null && label.isNotEmpty) ? label : id;

/// Everything a screen needs to draw one entry.
AuditLine auditLine(AppLocalizations l10n, AuditEvent e) {
  final facts = <AuditFact>[];

  // A fact with a value ("Art: Türkentaube"); skipped when there is no value
  // to show, so an absent field never renders as a dangling label.
  void add(String label, String? value) {
    if (value == null || value.isEmpty) return;
    facts.add(AuditFact(label, value));
  }

  // A fact that IS its label ("Wiedererkannter Vogel", "Mindestens ein
  // Fehlversuch in 5 Minuten") — the statement carries no separate value.
  void flag(String label) => facts.add(AuditFact(label, ''));

  switch (e.detail) {
    case CaseIntakeDetail(
      :final species,
      :final reidentified,
      :final hasFinder,
    ):
      add(l10n.auditFactSpecies, species);
      if (reidentified) flag(l10n.auditFactReidentified);
      if (hasFinder) flag(l10n.auditFactFinder);
    case CaseHandoffDetail(
      :final to,
      :final from,
      :final toLabel,
      :final fromLabel,
    ):
      // The name the server snapshotted, falling back to the id only for rows
      // written before it recorded one (federfall-ybua.1).
      add(l10n.auditFactHandoffTo, _named(toLabel, to));
      // Who handed it over is almost always the actor, and repeating the name
      // from the line above says nothing.
      if (from != null && from.isNotEmpty && from != e.actorId) {
        add(l10n.auditFactHandoffFrom, _named(fromLabel, from));
      }
    case CaseShareDetail(:final withUser, :final withLabel, :final access):
      add(l10n.auditFactSharedWith, _named(withLabel, withUser));
      if (access != null) {
        add(l10n.auditFactAccess, shareAccessLabel(l10n, access));
      }
    case RoleChangedDetail(:final from, :final to):
      if (from != null) add(l10n.auditFactRoleFrom, userRoleLabel(l10n, from));
      if (to != null) add(l10n.auditFactRoleTo, userRoleLabel(l10n, to));
    case AnimalMergedDetail(:final duplicateLabel, :final duplicateId):
      add(
        l10n.auditFactMergedInto,
        duplicateLabel.isEmpty ? duplicateId : duplicateLabel,
      );
    case ExamSavedDetail(:final findings, :final abnormal):
      add(l10n.auditFactFindings(findings), l10n.auditFactAbnormal(abnormal));
    case MicroscopySavedDetail(
      :final findings,
      :final sampleType,
      :final method,
      :final examinedBy,
      :final worstSeverity,
      :final noFindings,
      :final findingLabels,
      :final attachments,
    ):
      // „Kotprobe · Flotation" — the preparation only qualifies the probe, and
      // is never set for a crop swab.
      if (sampleType != null) {
        final probe = [
          microscopySampleTypeLabel(l10n, sampleType),
          if (method != null) microscopyMethodLabel(l10n, method),
        ].join(' · ');
        add(l10n.microscopyFieldSampleType, probe);
      }
      if (examinedBy != null) {
        add(
          l10n.microscopyFieldExaminedBy,
          microscopyExaminedByLabel(l10n, examinedBy),
        );
      }
      // The three states the sample can be in. "Nothing found" and "nobody has
      // looked yet" must not read the same — with a lab that is the normal
      // state for a day or two.
      if (noFindings) {
        flag(l10n.microscopyFieldNoFindings);
      } else if (findings == 0) {
        flag(l10n.microscopyResultPending);
      } else {
        // The NAMES the terms had at the time, not their ids — the vocabulary
        // is editable, so resolving one now would change what this row says
        // about the past (federfall-qt96).
        add(l10n.auditFactFindings(findings), findingLabels.join(', '));
      }
      if (worstSeverity != null) {
        add(
          l10n.microscopyFieldSeverity,
          microscopySeverityLabel(worstSeverity),
        );
      }
      if (attachments > 0) {
        add(l10n.auditFieldAttachments, '$attachments');
      }
    case ReportExportedDetail(:final format, :final year, :final rows):
      add(l10n.auditFactFormat, format.toUpperCase());
      add(l10n.auditFactPeriod, year?.toString() ?? l10n.auditFactPeriodAll);
      if (rows != null) flag(l10n.auditFactRows(rows));
    case CaseReportPrintedDetail(:final format):
      add(l10n.auditFactFormat, format.toUpperCase());
    case LoginDetail(:final method, :final provider, :final newAccount):
      add(l10n.auditFactMethod, method);
      add(l10n.auditFactProvider, provider);
      if (newAccount) flag(l10n.auditFactNewAccount);
    case LoginFailedDetail(:final windowMinutes):
      // Deliberately not a count: the server collapses a whole window into one
      // row, and showing "1" would read as "one attempt".
      flag(l10n.auditFactFailureWindow(windowMinutes));
    case UserProvisionedDetail(:final role, :final firstUser):
      if (role != null) add(l10n.auditFactRole, userRoleLabel(l10n, role));
      if (firstUser) flag(l10n.auditFactFirstUser);
    case DispositionDetail(
      :final caseStatus,
      :final lifetimeStatus,
      :final currentAviaryLabel,
    ):
      // What the disposition DID, not just that it was recorded. On a delete
      // this is the whole point: removing the last one reopens the case.
      if (caseStatus != null) {
        add(l10n.auditFactCaseNow, caseStatusLabel(l10n, caseStatus));
      }
      if (lifetimeStatus != null) {
        add(l10n.auditFactAnimalNow, lifetimeStatusLabel(l10n, lifetimeStatus));
      }
      // Where the bird still is. Only ever the label — an aviary id would say
      // less than nothing here.
      add(l10n.aviaryDetailTitle, currentAviaryLabel);
    case AuditPurgedDetail(:final count, :final retentionDays):
      flag(l10n.auditFactPurgedCount(count));
      if (retentionDays != null) {
        flag(l10n.auditFactRetentionDays(retentionDays));
      }
    case NoDetail() || UnknownDetail():
      break;
  }

  // `tokenKey` is not a field anybody set. PocketBase rotates it whenever an
  // account's password or email changes, and rotating it is what signs every
  // existing session for that account out — so it is a CONSEQUENCE, and the one
  // place that consequence is visible at all. Rendered as a change it read
  // "tokenKey: geändert (Wert nicht protokolliert)": a raw column name (it is a
  // system field, so the schema sweep in test_rules.py does not reach it) whose
  // value is withheld anyway, sitting next to the password line that already
  // said what happened. It is worth more as a plain statement of what it did.
  final sessionsEnded = e.changes.any((c) => c.field == 'tokenKey');
  final changes = sessionsEnded
      ? e.changes.where((c) => c.field != 'tokenKey').toList()
      : e.changes;

  if (changes.isNotEmpty) {
    // A create or a delete carries CONTENT, not a diff: every entry has one
    // side only. Rendering those through the diff wording gives "2 Felder
    // geändert: Ausgang: gesetzt auf Verstorben · …" for something that
    // changed nothing — it recorded an outcome. Show them as what they are.
    final isDiff = changes.any(
      (c) =>
          !c.redacted &&
          (c.fromDisplay?.isNotEmpty ?? false) &&
          (c.toDisplay?.isNotEmpty ?? false),
    );
    if (isDiff) {
      add(
        l10n.auditChangeSummary(changes.length),
        changes
            .take(3)
            .map(
              (c) =>
                  '${auditFieldLabel(l10n, e.subjectCollection, c.field)}: '
                  '${auditChangeText(l10n, e.subjectCollection, c)}',
            )
            .join(' · '),
      );
    } else {
      for (final c in changes) {
        add(
          auditFieldLabel(l10n, e.subjectCollection, c.field),
          c.redacted
              ? l10n.auditChangeRedacted
              // A create records only `to`, a delete only `from`; whichever
              // side is there is what this event was about.
              : auditChangeSide(
                  l10n,
                  e.subjectCollection,
                  c,
                  newValue: c.toDisplay?.isNotEmpty ?? false,
                ),
        );
      }
    }
  }

  // After the changes, because it is what they caused.
  if (sessionsEnded) flag(l10n.auditFactSessionsEnded);

  if (e.ip != null && e.ip!.isNotEmpty) add(l10n.auditFactIp, e.ip);

  // Which case, by its number (federfall-by7w.2). Last, because it is context
  // rather than content — and skipped when the subject IS the case, where it
  // would repeat the subtitle verbatim.
  if (e.caseLabel.isNotEmpty && e.caseLabel != e.subjectLabel) {
    add(l10n.auditFactCase, e.caseLabel);
  }

  // The subtitle is the subject label with nothing to say what it IS, so when a
  // labelled fact already names the same thing, that fact is the better of the
  // two: „Übernommen von: Bernd Weber" over a bare „Bernd Weber" repeated.
  final named = facts.any((f) => f.value == e.subjectLabel);

  return AuditLine(
    title: auditActionTitle(l10n, e.action, e.rawAction),
    subtitle: e.subjectLabel.isNotEmpty && !named ? e.subjectLabel : null,
    facts: facts,
    icon: auditIcon(e),
  );
}
