import 'package:federfall/l10n/gen/app_localizations.dart';
import 'package:federfall_models/federfall_models.dart';

/// Localized display labels for the case code lists. The enums carry only the
/// wire value PocketBase stores; the user-facing names live in the arb files
/// and are resolved here (same pattern as `Validators`).
String admissionReasonLabel(AppLocalizations l10n, AdmissionReason r) =>
    switch (r) {
      AdmissionReason.injury => l10n.caseReasonInjury,
      AdmissionReason.illness => l10n.caseReasonIllness,
      AdmissionReason.orphaned => l10n.caseReasonOrphaned,
      AdmissionReason.trauma => l10n.caseReasonTrauma,
      AdmissionReason.poisoning => l10n.caseReasonPoisoning,
      AdmissionReason.trapped => l10n.caseReasonTrapped,
      AdmissionReason.catAttack => l10n.caseReasonCatAttack,
      AdmissionReason.collision => l10n.caseReasonCollision,
      AdmissionReason.oiled => l10n.caseReasonOiled,
      AdmissionReason.entangled => l10n.caseReasonEntangled,
      AdmissionReason.weakEmaciated => l10n.caseReasonWeakEmaciated,
      AdmissionReason.other => l10n.caseReasonOther,
    };

String caseStatusLabel(AppLocalizations l10n, CaseStatus s) => switch (s) {
  CaseStatus.inCare => l10n.caseStatusInCare,
  CaseStatus.inTreatment => l10n.caseStatusInTreatment,
  CaseStatus.rehab => l10n.caseStatusRehab,
  CaseStatus.readyForRelease => l10n.caseStatusReadyForRelease,
  CaseStatus.disposed => l10n.caseStatusDisposed,
};
