import 'package:federfall/l10n/gen/app_localizations.dart';
import 'package:federfall_models/federfall_models.dart';

/// Localized display labels for the case code lists. The enums carry only the
/// wire value PocketBase stores; the user-facing names live in the arb files
/// and are resolved here (same pattern as `Validators`).
///
/// Admission reasons are a supervisor-managed code list (not an enum); resolve
/// their labels via the `admissionReasonsById` provider instead.
String caseStatusLabel(AppLocalizations l10n, CaseStatus s) => switch (s) {
  CaseStatus.inCare => l10n.caseStatusInCare,
  CaseStatus.readyForRelease => l10n.caseStatusReadyForRelease,
  CaseStatus.disposed => l10n.caseStatusDisposed,
};

String lifetimeStatusLabel(AppLocalizations l10n, LifetimeStatus s) =>
    switch (s) {
      LifetimeStatus.inCare => l10n.lifetimeStatusInCare,
      LifetimeStatus.atLargeReleased => l10n.lifetimeStatusAtLargeReleased,
      LifetimeStatus.inAviary => l10n.lifetimeStatusInAviary,
      LifetimeStatus.deceased => l10n.lifetimeStatusDeceased,
    };

String shareAccessLabel(AppLocalizations l10n, ShareAccess a) => switch (a) {
  ShareAccess.read => l10n.caseShareAccessRead,
  ShareAccess.edit => l10n.caseShareAccessEdit,
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

/// Null means the server carries a disposition type this app version does not
/// know — shown as "unknown" rather than guessing an outcome.
String dispositionTypeLabel(AppLocalizations l10n, DispositionType? t) =>
    switch (t) {
      DispositionType.released => l10n.dispositionReleased,
      DispositionType.placedInAviary => l10n.dispositionPlacedInAviary,
      DispositionType.died => l10n.dispositionDied,
      DispositionType.euthanized => l10n.dispositionEuthanized,
      DispositionType.transferred => l10n.dispositionTransferred,
      DispositionType.returnedToOwner => l10n.dispositionReturnedToOwner,
      null => l10n.dispositionUnknown,
    };

String hydrationLabel(AppLocalizations l10n, Hydration h) => switch (h) {
  Hydration.normal => l10n.hydrationNormal,
  Hydration.mild => l10n.hydrationMild,
  Hydration.moderate => l10n.hydrationModerate,
  Hydration.severe => l10n.hydrationSevere,
};

String mentationLabel(AppLocalizations l10n, Mentation m) => switch (m) {
  Mentation.bright => l10n.mentationBright,
  Mentation.quiet => l10n.mentationQuiet,
  Mentation.depressed => l10n.mentationDepressed,
  Mentation.unresponsive => l10n.mentationUnresponsive,
};

String bodySystemLabel(AppLocalizations l10n, BodySystem s) => switch (s) {
  BodySystem.eyes => l10n.bodySystemEyes,
  BodySystem.beakNares => l10n.bodySystemBeakNares,
  BodySystem.oral => l10n.bodySystemOral,
  BodySystem.integument => l10n.bodySystemIntegument,
  BodySystem.wings => l10n.bodySystemWings,
  BodySystem.legsFeet => l10n.bodySystemLegsFeet,
  BodySystem.keel => l10n.bodySystemKeel,
  BodySystem.respiratory => l10n.bodySystemRespiratory,
  BodySystem.coelom => l10n.bodySystemCoelom,
  BodySystem.neuro => l10n.bodySystemNeuro,
  BodySystem.vent => l10n.bodySystemVent,
};

String findingStatusLabel(AppLocalizations l10n, FindingStatus s) =>
    switch (s) {
      FindingStatus.normal => l10n.findingStatusNormal,
      FindingStatus.abnormal => l10n.findingStatusAbnormal,
    };

String mmColorLabel(AppLocalizations l10n, MmColor c) => switch (c) {
  MmColor.pink => l10n.mmColorPink,
  MmColor.pale => l10n.mmColorPale,
  MmColor.cyanotic => l10n.mmColorCyanotic,
  MmColor.icteric => l10n.mmColorIcteric,
  MmColor.injected => l10n.mmColorInjected,
};

String mmTextureLabel(AppLocalizations l10n, MmTexture t) => switch (t) {
  MmTexture.moist => l10n.mmTextureMoist,
  MmTexture.tacky => l10n.mmTextureTacky,
  MmTexture.dry => l10n.mmTextureDry,
};
