// Domain enums mirroring the PocketBase select fields. Each constant carries a
// [wire] value — the exact string PocketBase stores — so mapping survives a
// rename of the Dart identifier and never leaks snake_case into the codebase.

import 'package:federfall_models/src/converters.dart';

/// Staff role within an organisation (`users.role`).
enum UserRole {
  carer('carer'),
  coordinator('coordinator'),
  supervisor('supervisor');

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

/// Reason(s) a bird was admitted (`cases.reasons_for_admission`, multi-select).
enum AdmissionReason {
  injury('injury'),
  illness('illness'),
  orphaned('orphaned'),
  trauma('trauma'),
  poisoning('poisoning'),
  trapped('trapped'),
  catAttack('cat_attack'),
  collision('collision'),
  oiled('oiled'),
  entangled('entangled'),
  weakEmaciated('weak_emaciated'),
  other('other');

  const AdmissionReason(this.wire);

  final String wire;

  static AdmissionReason? fromWire(Object? v) =>
      pbEnum(values, (e) => e.wire, v);

  static List<AdmissionReason> listFromWire(Object? v) =>
      pbEnumList(values, (e) => e.wire, v);
}

/// Lifecycle status of a case (`cases.status`).
enum CaseStatus {
  inCare('in_care'),
  inTreatment('in_treatment'),
  rehab('rehab'),
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
