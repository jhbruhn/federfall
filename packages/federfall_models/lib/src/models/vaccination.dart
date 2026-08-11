import 'package:federfall_models/src/converters.dart';
import 'package:federfall_models/src/enums.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:pocketbase/pocketbase.dart';

part 'vaccination.freezed.dart';

/// One vaccination given to an animal (1700000087).
///
/// A longitudinal property of the ANIMAL, not of a case — there is deliberately
/// no `case` field, the stance `EggRecord` and `Weight` take. A PMV shot given
/// during a spring case is exactly what the next keeper needs two years later,
/// under a different case, so timeline membership is computed from the animal
/// rather than stored.
///
/// [vaccine] and [target] are free text: the vocabulary comes from the
/// `vaccine_labels` view over what this org has actually recorded, which
/// suggests without owning the value. A row therefore still reads correctly
/// after the team changes what it calls something.
///
/// [administeredAt] is optional in the schema and falls back to [created], the
/// way `weights.measured_at` does.
@freezed
abstract class Vaccination with _$Vaccination {
  const factory Vaccination({
    required String id,
    required String animal,

    /// The product as written on the vial, e.g. "Colombovac PMV".
    required String vaccine,

    /// What it protects against, e.g. "Paramyxovirose" — one field, because a
    /// combination vaccine is still ONE administration.
    String? target,
    DateTime? administeredAt,

    /// Chargennummer. The field that makes a vaccine failure or a recall
    /// traceable, and the reason a journal note was never enough.
    String? batch,
    double? dose,

    /// Millilitres unless somebody says otherwise — the schema has no defaults,
    /// so this one lives here and in the entry sheet.
    @Default('ml') String doseUnit,

    /// `medication_routes` id — the same vocabulary prescriptions use.
    String? route,
    VaccinationSeries? series,

    /// When the booster is due. Stored rather than derived: what was planned at
    /// the time must not move because an interval was edited later.
    DateTime? nextDueAt,

    /// The external practice or vet who gave it. In-house administration is
    /// carried by [author], which the server pins to the caller.
    String? vet,
    String? notes,

    /// Up to three images — a vial label, or a paper Impfausweis that came with
    /// the bird.
    @Default(<String>[]) List<String> attachments,
    String? author,
    String? org,
    DateTime? created,
    DateTime? updated,
  }) = _Vaccination;

  factory Vaccination.fromRecord(RecordModel r) {
    final d = r.data;
    return Vaccination(
      id: r.id,
      animal: pbString(d['animal']) ?? '',
      vaccine: pbString(d['vaccine']) ?? '',
      target: pbString(d['target']),
      administeredAt: pbDate(d['administered_at']),
      batch: pbString(d['batch']),
      // pbQuantity, not pbDouble: PocketBase returns 0 for an unset number, and
      // "0 ml" is not a dose anybody gave.
      dose: pbQuantity(d['dose']),
      doseUnit: pbString(d['dose_unit']) ?? 'ml',
      route: pbString(d['route']),
      series: VaccinationSeries.fromWire(d['series']),
      nextDueAt: pbDate(d['next_due_at']),
      vet: pbString(d['vet']),
      notes: pbString(d['notes']),
      attachments: pbStringList(d['attachments']),
      author: pbString(d['author']),
      org: pbString(d['org']),
      created: pbDate(d['created']),
      updated: pbDate(d['updated']),
    );
  }

  const Vaccination._();

  /// When this shot was given, falling back to when it was recorded — the one
  /// ordering every reader uses (the ledger, the case-timeline window, and the
  /// `vaccine_labels` view's own `last_used_at`).
  DateTime? get at => administeredAt ?? created;

  /// Whether the booster is due on or before [now] (default: this moment). Null
  /// [nextDueAt] means nothing was planned, which is not the same as due.
  bool isDue({DateTime? now}) {
    final due = nextDueAt;
    return due != null && !due.isAfter(now ?? DateTime.now());
  }
}
