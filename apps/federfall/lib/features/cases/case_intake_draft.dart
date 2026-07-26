import 'dart:convert';

import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/foundation.dart';

/// A snapshot of an in-progress intake wizard, persisted so an interrupted
/// intake survives the app being killed (federfall-t2is).
///
/// `NewCaseScreen` is the biggest form in the app — three steps, ~20 fields,
/// staged photos — and the app is online-only, so a half-finished intake
/// exists nowhere but that widget's `State`. An incoming call, an OS
/// low-memory eviction or a crash used to lose all of it, which is exactly the
/// field scenario: a phone in one hand and a bird in the other.
///
/// Two deliberate shapes here:
///
/// * Text values are the RAW controller text, not parsed numbers, so a
///   round-trip through storage cannot change what the carer sees on restore.
/// * Times travel as UTC and come back local, matching how the wizard submits
///   them. Both date fields are date-only pickers, and the round-trip is
///   exact, so no value shifts across midnight.
@immutable
class CaseIntakeDraft {
  const CaseIntakeDraft({
    required this.savedAt,
    required this.idempotencyKey,
    required this.step,
    this.routeAnimalId,
    this.linkedAnimalId,
    this.species = '',
    this.name = '',
    this.reasons = const [],
    this.ageClass,
    this.foundAt,
    this.admittedAt,
    this.findLocation = '',
    this.findGeo,
    this.findCity,
    this.findRegion,
    this.intakeWeight = '',
    this.quarantineDays = '',
    this.intakeNotes = '',
    this.finderFirstName = '',
    this.finderLastName = '',
    this.finderPhone = '',
    this.finderEmail = '',
    this.finderCity = '',
    this.photoPaths = const [],
    this.withExam = false,
    this.partial = false,
  });

  /// Bumped whenever the persisted shape changes. A draft written by another
  /// version is dropped rather than migrated — it is at most a few hours of
  /// one unfinished form, never worth a migration path.
  static const schemaVersion = 1;

  /// How long a draft stays offerable. Beyond this the wizard purges it: an
  /// intake nobody finished within a day is stale enough that restoring it
  /// risks attaching yesterday's notes to today's bird.
  static const maxAge = Duration(hours: 24);

  /// When this snapshot was taken — shown in the restore prompt so the carer
  /// can tell whether the draft is theirs.
  final DateTime savedAt;

  /// The wizard's idempotency key, restored along with the values.
  ///
  /// This is what makes a crash *during* submit recoverable: the intake may
  /// already have committed server-side, and resubmitting the same key makes
  /// the backend replay it instead of admitting the bird twice
  /// (federfall-3ty3, now extended across process death).
  final String idempotencyKey;

  /// Which wizard step was on screen (0 animal, 1 admission, 2 docs/finder).
  final int step;

  /// The `animalId` route argument this draft was started with, if any. A
  /// draft is only offered back when it matches — a draft begun from an
  /// aviary resident must not resurface on a blank intake.
  final String? routeAnimalId;

  /// The re-identified existing animal the case was to be linked to.
  final String? linkedAnimalId;

  final String species;
  final String name;

  /// Selected `admission_reasons` ids.
  final List<String> reasons;

  final AgeClass? ageClass;
  final DateTime? foundAt;
  final DateTime? admittedAt;
  final String findLocation;
  final GeoPoint? findGeo;
  final String? findCity;
  final String? findRegion;
  final String intakeWeight;
  final String quarantineDays;
  final String intakeNotes;
  final String finderFirstName;
  final String finderLastName;
  final String finderPhone;
  final String finderEmail;
  final String finderCity;

  /// Paths of the staged intake photos.
  ///
  /// `image_picker` hands back files in a cache directory the OS may clear at
  /// any time, so a path can outlive its bytes — a restore must verify each
  /// one rather than trust the list.
  final List<String> photoPaths;

  final bool withExam;

  /// Whether values the wizard held were dropped when this draft was stored,
  /// so the restore can say so instead of silently losing them. Set by
  /// [forPlaintextStore].
  final bool partial;

  /// Whether any finder contact field carries input.
  bool get hasFinder =>
      finderFirstName.trim().isNotEmpty ||
      finderLastName.trim().isNotEmpty ||
      finderPhone.trim().isNotEmpty ||
      finderEmail.trim().isNotEmpty ||
      finderCity.trim().isNotEmpty;

  /// Whether this draft is too old to offer back, as of [now].
  bool isStaleAt(DateTime now) => now.difference(savedAt) > maxAge;

  /// The subset of this draft that is safe and useful to keep in plaintext
  /// storage — see `PrefsCaseIntakeDraftStore`, the web fallback.
  ///
  /// Drops the finder's contact details. Those are a THIRD PARTY's PII, and
  /// unlike the auth token (`auth_token_storage.dart`, which documents why
  /// localStorage is an accepted risk for the user's OWN bearer token) there
  /// is no equivalent argument for writing someone else's phone number and
  /// address into a script-readable store. The backend runs a
  /// `finder_retention` cron precisely to scrub this class of data.
  ///
  /// Also drops the staged photo paths: on web those are `blob:` URLs that die
  /// with the document, so keeping them would only produce dead entries.
  CaseIntakeDraft forPlaintextStore() => CaseIntakeDraft(
    savedAt: savedAt,
    idempotencyKey: idempotencyKey,
    step: step,
    routeAnimalId: routeAnimalId,
    linkedAnimalId: linkedAnimalId,
    species: species,
    name: name,
    reasons: reasons,
    ageClass: ageClass,
    foundAt: foundAt,
    admittedAt: admittedAt,
    findLocation: findLocation,
    findGeo: findGeo,
    findCity: findCity,
    findRegion: findRegion,
    intakeWeight: intakeWeight,
    quarantineDays: quarantineDays,
    intakeNotes: intakeNotes,
    // photoPaths deliberately left at its empty default — see above.
    withExam: withExam,
    partial: partial || hasFinder || photoPaths.isNotEmpty,
  );

  Map<String, dynamic> toJson() => {
    'v': schemaVersion,
    'saved_at': savedAt.toUtc().toIso8601String(),
    'idempotency_key': idempotencyKey,
    'step': step,
    'route_animal_id': ?routeAnimalId,
    'linked_animal_id': ?linkedAnimalId,
    'species': species,
    'name': name,
    'reasons': reasons,
    'age_class': ?ageClass?.wire,
    'found_at': ?foundAt?.toUtc().toIso8601String(),
    'admitted_at': ?admittedAt?.toUtc().toIso8601String(),
    'find_location': findLocation,
    if (findGeo case final geo?) 'find_geo': {'lon': geo.lon, 'lat': geo.lat},
    'find_city': ?findCity,
    'find_region': ?findRegion,
    'intake_weight': intakeWeight,
    'quarantine_days': quarantineDays,
    'intake_notes': intakeNotes,
    'finder_first_name': finderFirstName,
    'finder_last_name': finderLastName,
    'finder_phone': finderPhone,
    'finder_email': finderEmail,
    'finder_city': finderCity,
    'photo_paths': photoPaths,
    'with_exam': withExam,
    'partial': partial,
  };

  /// Rebuilds a draft from [json], or `null` when it is not a readable draft
  /// of the current [schemaVersion]. Every field is read defensively: a draft
  /// is untrusted input (a hand-edited localStorage entry, or a leftover from
  /// a build that shaped it differently), and a malformed one must degrade to
  /// "no draft" rather than throw on the wizard's first frame.
  static CaseIntakeDraft? fromJson(Map<String, dynamic> json) {
    if (_int(json['v']) != schemaVersion) return null;
    final savedAt = _date(json['saved_at']);
    final key = _str(json['idempotency_key']);
    if (savedAt == null || key == null || key.isEmpty) return null;
    return CaseIntakeDraft(
      savedAt: savedAt,
      idempotencyKey: key,
      step: _int(json['step']) ?? 0,
      routeAnimalId: _str(json['route_animal_id']),
      linkedAnimalId: _str(json['linked_animal_id']),
      species: _str(json['species']) ?? '',
      name: _str(json['name']) ?? '',
      reasons: _strings(json['reasons']),
      ageClass: AgeClass.fromWire(json['age_class']),
      foundAt: _date(json['found_at']),
      admittedAt: _date(json['admitted_at']),
      findLocation: _str(json['find_location']) ?? '',
      findGeo: GeoPoint.fromPb(json['find_geo']),
      findCity: _str(json['find_city']),
      findRegion: _str(json['find_region']),
      intakeWeight: _str(json['intake_weight']) ?? '',
      quarantineDays: _str(json['quarantine_days']) ?? '',
      intakeNotes: _str(json['intake_notes']) ?? '',
      finderFirstName: _str(json['finder_first_name']) ?? '',
      finderLastName: _str(json['finder_last_name']) ?? '',
      finderPhone: _str(json['finder_phone']) ?? '',
      finderEmail: _str(json['finder_email']) ?? '',
      finderCity: _str(json['finder_city']) ?? '',
      photoPaths: _strings(json['photo_paths']),
      withExam: _bool(json['with_exam']),
      partial: _bool(json['partial']),
    );
  }

  String encode() => jsonEncode(toJson());

  /// Decodes what a store read back, tolerating anything that is not a draft.
  static CaseIntakeDraft? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? fromJson(decoded) : null;
    } on FormatException {
      return null;
    }
  }
}

String? _str(Object? v) => v is String ? v : null;

int? _int(Object? v) => v is num ? v.toInt() : null;

bool _bool(Object? v) => v is bool && v;

DateTime? _date(Object? v) =>
    v is String ? DateTime.tryParse(v)?.toLocal() : null;

List<String> _strings(Object? v) => v is List
    ? [
        for (final e in v)
          if (e is String) e,
      ]
    : const [];
