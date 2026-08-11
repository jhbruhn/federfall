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

/// Whether an egg was fertile (`egg_records.fertility`).
enum EggFertility {
  unknown('unknown'),
  fertile('fertile'),
  infertile('infertile');

  const EggFertility(this.wire);

  final String wire;

  static EggFertility? fromWire(Object? v) => pbEnum(values, (e) => e.wire, v);
}

/// What happened to an egg after it was laid (`egg_records.fate`).
enum EggFate {
  inNest('in_nest'),

  /// Replaced with a dummy egg so the pair keeps brooding without breeding.
  dummySwapped('dummy_swapped'),
  removed('removed'),
  hatched('hatched'),
  broken('broken'),
  discarded('discarded'),
  unknown('unknown');

  const EggFate(this.wire);

  final String wire;

  static EggFate? fromWire(Object? v) => pbEnum(values, (e) => e.wire, v);
}

/// How sure we are that this animal is the layer (`egg_records.attribution`).
///
/// In a pair you often cannot tell which hen laid a clutch until later, so the
/// doubt is recorded rather than silently asserted as fact. Reassigning the
/// record flips it to [confirmed].
enum EggAttribution {
  confirmed('confirmed'),
  presumed('presumed');

  const EggAttribution(this.wire);

  final String wire;

  static EggAttribution? fromWire(Object? v) =>
      pbEnum(values, (e) => e.wire, v);
}

/// Whether a shot was part of the initial course or a top-up
/// (`vaccinations.series`).
///
/// Deliberately not a dose counter: "2 of 3" is a property of a schedule this
/// app does not model, and a rehab rarely knows what a bird already had.
enum VaccinationSeries {
  /// Grundimmunisierung.
  primary('primary'),

  /// Auffrischung.
  booster('booster');

  const VaccinationSeries(this.wire);

  final String wire;

  static VaccinationSeries? fromWire(Object? v) =>
      pbEnum(values, (e) => e.wire, v);
}

/// Which kind of sample was looked at under the microscope
/// (`microscopy_samples.sample_type`): a crop swab or a faecal sample.
enum MicroscopySampleType {
  cropSwab('crop_swab'),
  fecal('fecal');

  const MicroscopySampleType(this.wire);

  final String wire;

  static MicroscopySampleType? fromWire(Object? v) =>
      pbEnum(values, (e) => e.wire, v);
}

/// How a faecal sample was prepared (`microscopy_samples.method`).
///
/// Faecal only — the route clears it for a crop swab, so "Kropfabstrich,
/// Flotation" is unstorable.
enum MicroscopyMethod {
  directSmear('direct_smear'),
  flotation('flotation');

  const MicroscopyMethod(this.wire);

  final String wire;

  static MicroscopyMethod? fromWire(Object? v) =>
      pbEnum(values, (e) => e.wire, v);
}

/// Who did the analysis (`microscopy_samples.examined_by`) — three-valued
/// rather than a bool, because a veterinary practice is not a laboratory.
enum MicroscopyExaminedBy {
  inHouse('in_house'),
  vet('vet'),
  lab('lab');

  const MicroscopyExaminedBy(this.wire);

  final String wire;

  static MicroscopyExaminedBy? fromWire(Object? v) =>
      pbEnum(values, (e) => e.wire, v);
}

/// How strongly a finding was present (`microscopy_findings.severity`),
/// rendered `+` / `++` / `+++` and ordered weakest first.
///
/// The wire values spell the grade out instead of storing literal plus signs:
/// they end up in filter expressions, CSV cells and audit rows, where a bare
/// `+` is at best unreadable and at worst needs escaping.
enum MicroscopySeverity {
  plus('plus'),
  plusPlus('plus_plus'),
  plusPlusPlus('plus_plus_plus');

  const MicroscopySeverity(this.wire);

  final String wire;

  static MicroscopySeverity? fromWire(Object? v) =>
      pbEnum(values, (e) => e.wire, v);
}

/// How often a Patenschaft is given (`sponsorships.interval`).
///
/// `oneTime` is a single donation rather than a rhythm, and is deliberately in
/// the same enum: a rehab that received one payment for a bird still calls it a
/// Patenschaft, and a separate boolean beside a nullable interval would make
/// "monthly AND one-off" expressible.
enum SponsorshipInterval {
  monthly('monthly'),
  quarterly('quarterly'),
  yearly('yearly'),
  oneTime('one_time');

  const SponsorshipInterval(this.wire);

  final String wire;

  static SponsorshipInterval? fromWire(Object? v) =>
      pbEnum(values, (e) => e.wire, v);
}
