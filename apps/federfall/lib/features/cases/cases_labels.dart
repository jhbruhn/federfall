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

String sexLabel(AppLocalizations l10n, Sex s) => switch (s) {
  Sex.male => l10n.sexMale,
  Sex.female => l10n.sexFemale,
  Sex.unknown => l10n.sexUnknown,
};

String ageClassLabel(AppLocalizations l10n, AgeClass a) => switch (a) {
  AgeClass.squab => l10n.ageClassSquab,
  AgeClass.fledgling => l10n.ageClassFledgling,
  AgeClass.immature => l10n.ageClassImmature,
  AgeClass.adult => l10n.ageClassAdult,
};

String certaintyLabel(AppLocalizations l10n, Certainty c) => switch (c) {
  Certainty.suspected => l10n.certaintySuspected,
  Certainty.confirmed => l10n.certaintyConfirmed,
};

/// A friendly label for a medication's dosing frequency, derived from the
/// structured [kind] + [intervalHours] (named presets for common intervals,
/// "every N h" otherwise). Empty when no frequency is recorded.
String medicationFrequencyLabel(
  AppLocalizations l10n,
  MedicationFrequencyKind? kind,
  int? intervalHours,
) {
  switch (kind) {
    case null:
      return '';
    case MedicationFrequencyKind.once:
      return l10n.freqOnce;
    case MedicationFrequencyKind.asNeeded:
      return l10n.freqAsNeeded;
    case MedicationFrequencyKind.scheduled:
      return switch (intervalHours) {
        24 => l10n.freqOnceDaily,
        12 => l10n.freqTwiceDaily,
        8 => l10n.freq3xDaily,
        6 => l10n.freq4xDaily,
        48 => l10n.freqEveryOtherDay,
        final h? => l10n.freqEveryNHours(h),
        null => '',
      };
  }
}

String dispositionTypeLabel(AppLocalizations l10n, DispositionType t) =>
    switch (t) {
      DispositionType.released => l10n.dispositionReleased,
      DispositionType.placedInAviary => l10n.dispositionPlacedInAviary,
      DispositionType.died => l10n.dispositionDied,
      DispositionType.euthanized => l10n.dispositionEuthanized,
      DispositionType.transferred => l10n.dispositionTransferred,
      DispositionType.returnedToOwner => l10n.dispositionReturnedToOwner,
    };

String medicationRouteLabel(AppLocalizations l10n, MedicationRoute r) =>
    switch (r) {
      MedicationRoute.oral => l10n.routeOral,
      MedicationRoute.subcutaneous => l10n.routeSubcutaneous,
      MedicationRoute.intramuscular => l10n.routeIntramuscular,
      MedicationRoute.intravenous => l10n.routeIntravenous,
      MedicationRoute.topical => l10n.routeTopical,
      MedicationRoute.nebulized => l10n.routeNebulized,
      MedicationRoute.other => l10n.routeOther,
    };

String markingTypeLabel(AppLocalizations l10n, MarkingType t) => switch (t) {
  MarkingType.finderRing => l10n.markingFinderRing,
  MarkingType.temporaryMarker => l10n.markingTemporaryMarker,
  MarkingType.releaseRing => l10n.markingReleaseRing,
  MarkingType.associationRing => l10n.markingAssociationRing,
  MarkingType.microchip => l10n.markingMicrochip,
};
