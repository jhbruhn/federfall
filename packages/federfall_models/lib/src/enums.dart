// Domain enums mirroring the PocketBase select fields. Each constant carries a
// [wire] value — the exact string PocketBase stores — so mapping survives a
// rename of the Dart identifier and never leaks snake_case into the codebase.

import 'package:federfall_models/src/converters.dart';

/// Staff role within an organisation (`users.role`).
enum UserRole {
  carer('carer'),
  coordinator('coordinator'),
  supervisor('supervisor'),

  /// A self-registered (OAuth2) account that has not yet been granted a real
  /// role. Guests can authenticate but the API access rules wall them off from
  /// all data until a supervisor promotes them.
  guest('guest');

  const UserRole(this.wire);

  final String wire;

  static UserRole? fromWire(Object? v) => pbEnum(values, (e) => e.wire, v);
}

/// Biological sex of an animal (`animals.sex`).
enum Sex {
  male('male'),
  female('female'),
  unknown('unknown');

  const Sex(this.wire);

  final String wire;

  static Sex? fromWire(Object? v) => pbEnum(values, (e) => e.wire, v);
}

/// Lifetime status of an animal, derived from its latest disposition
/// (`animals.lifetime_status`).
enum LifetimeStatus {
  inCare('in_care'),
  atLargeReleased('at_large_released'),
  inAviary('in_aviary'),
  deceased('deceased');

  const LifetimeStatus(this.wire);

  final String wire;

  static LifetimeStatus? fromWire(Object? v) =>
      pbEnum(values, (e) => e.wire, v);
}

/// Estimated age class of an admitted bird (`cases.age_class`).
enum AgeClass {
  squab('squab'),
  fledgling('fledgling'),
  immature('immature'),
  adult('adult');

  const AgeClass(this.wire);

  final String wire;

  static AgeClass? fromWire(Object? v) => pbEnum(values, (e) => e.wire, v);
}

/// Lifecycle status of a case (`cases.status`).
enum CaseStatus {
  inCare('in_care'),
  readyForRelease('ready_for_release'),
  disposed('disposed');

  const CaseStatus(this.wire);

  final String wire;

  static CaseStatus? fromWire(Object? v) => pbEnum(values, (e) => e.wire, v);
}

/// Kind of marking carried by an animal (`markings.type`).
enum MarkingType {
  finderRing('finder_ring'),
  temporaryMarker('temporary_marker'),
  releaseRing('release_ring'),
  associationRing('association_ring'),
  microchip('microchip');

  const MarkingType(this.wire);

  final String wire;

  static MarkingType? fromWire(Object? v) => pbEnum(values, (e) => e.wire, v);
}

/// Diagnostic certainty of a recorded condition (`case_conditions.certainty`).
enum Certainty {
  suspected('suspected'),
  confirmed('confirmed');

  const Certainty(this.wire);

  final String wire;

  static Certainty? fromWire(Object? v) => pbEnum(values, (e) => e.wire, v);
}

/// How often a medication is given (`medications.frequency_kind`). When
/// [scheduled], `interval_hours` carries the gap between doses, so a reminder
/// can compute the next due time.
enum MedicationFrequencyKind {
  once('once'),
  scheduled('scheduled'),
  asNeeded('as_needed');

  const MedicationFrequencyKind(this.wire);

  final String wire;

  static MedicationFrequencyKind? fromWire(Object? v) =>
      pbEnum(values, (e) => e.wire, v);
}

/// Route of administration for a medication (`medications.route`).
enum MedicationRoute {
  oral('oral'),
  subcutaneous('subcutaneous'),
  intramuscular('intramuscular'),
  intravenous('intravenous'),
  topical('topical'),
  nebulized('nebulized'),
  other('other');

  const MedicationRoute(this.wire);

  final String wire;

  static MedicationRoute? fromWire(Object? v) =>
      pbEnum(values, (e) => e.wire, v);
}

/// Outcome of a case (`dispositions.type`).
enum DispositionType {
  released('released'),
  placedInAviary('placed_in_aviary'),
  died('died'),
  euthanized('euthanized'),
  transferred('transferred'),
  returnedToOwner('returned_to_owner');

  const DispositionType(this.wire);

  final String wire;

  static DispositionType? fromWire(Object? v) =>
      pbEnum(values, (e) => e.wire, v);
}

/// Access level granted by a case share (`case_shares.access`).
enum ShareAccess {
  read('read'),
  edit('edit');

  const ShareAccess(this.wire);

  final String wire;

  static ShareAccess? fromWire(Object? v) => pbEnum(values, (e) => e.wire, v);
}

/// Hydration assessment on a structured exam (`exams.hydration`), ordered from
/// well-hydrated to severely dehydrated (≈5 / 7 / ≥10 %).
enum Hydration {
  normal('normal'),
  mild('mild'),
  moderate('moderate'),
  severe('severe');

  const Hydration(this.wire);

  final String wire;

  static Hydration? fromWire(Object? v) => pbEnum(values, (e) => e.wire, v);
}

/// Attitude / mentation on a structured exam (`exams.mentation`), the clinical
/// BAR → QAR → depressed → non-responsive scale.
enum Mentation {
  bright('bright'),
  quiet('quiet'),
  depressed('depressed'),
  unresponsive('unresponsive');

  const Mentation(this.wire);

  final String wire;

  static Mentation? fromWire(Object? v) => pbEnum(values, (e) => e.wire, v);
}

/// A body region assessed on a structured exam (`exam_findings.system`).
enum BodySystem {
  eyes('eyes'),
  beakNares('beak_nares'),
  oral('oral'),
  integument('integument'),
  wings('wings'),
  legsFeet('legs_feet'),
  keel('keel'),
  respiratory('respiratory'),
  coelom('coelom'),
  neuro('neuro'),
  vent('vent');

  const BodySystem(this.wire);

  final String wire;

  static BodySystem? fromWire(Object? v) => pbEnum(values, (e) => e.wire, v);
}

/// Whether an assessed body system was normal or abnormal
/// (`exam_findings.status`).
enum FindingStatus {
  normal('normal'),
  abnormal('abnormal');

  const FindingStatus(this.wire);

  final String wire;

  static FindingStatus? fromWire(Object? v) => pbEnum(values, (e) => e.wire, v);
}

/// Mucous-membrane colour on a structured exam (`exams.mm_color`).
enum MmColor {
  pink('pink'),
  pale('pale'),
  cyanotic('cyanotic'),
  icteric('icteric'),
  injected('injected');

  const MmColor(this.wire);

  final String wire;

  static MmColor? fromWire(Object? v) => pbEnum(values, (e) => e.wire, v);
}

/// Mucous-membrane texture on a structured exam (`exams.mm_texture`).
enum MmTexture {
  moist('moist'),
  tacky('tacky'),
  dry('dry');

  const MmTexture(this.wire);

  final String wire;

  static MmTexture? fromWire(Object? v) => pbEnum(values, (e) => e.wire, v);
}
