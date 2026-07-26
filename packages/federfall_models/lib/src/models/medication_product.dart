import 'package:federfall_models/src/converters.dart';
import 'package:federfall_models/src/enums.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:pocketbase/pocketbase.dart';

part 'medication_product.freezed.dart';

/// An entry in the org's drug catalogue (federfall-6d3a.3): the protocol for
/// one preparation, maintained by a supervisor.
///
/// It exists so a carer writing a prescription does not re-type the numbers
/// off a bottle, and so those numbers have an owner — the org's vet, not this
/// repository. Every field except [label] is optional: an entry that only names
/// a drug is still useful, and nothing here is a clinical guarantee.
///
/// [doseRate], [rateMin], [rateMax] and [concentrationPerMl] are all expressed
/// in [doseUnit], the same single-unit rule the prescription follows (see the
/// 1700000058 migration) — so a catalogue entry can be poured straight into a
/// plan without a unit conversion anywhere.
@freezed
abstract class MedicationProduct with _$MedicationProduct {
  const factory MedicationProduct({
    required String id,
    required String label,
    String? doseUnit,
    double? doseRate,

    /// The range a prescribed rate is sanity-checked against. Advisory: the
    /// form warns outside it rather than refusing, because the vet in front of
    /// the bird outranks the catalogue.
    double? rateMin,
    double? rateMax,
    double? concentrationPerMl,

    /// Default route, referencing the org's `medication_routes` code list.
    String? route,
    MedicationFrequencyKind? frequencyKind,
    int? intervalHours,
    String? note,
    @Default(true) bool active,
    String? org,
    DateTime? created,
    DateTime? updated,
  }) = _MedicationProduct;

  const MedicationProduct._();

  factory MedicationProduct.fromRecord(RecordModel r) {
    final d = r.data;
    return MedicationProduct(
      id: r.id,
      label: pbString(d['label']) ?? '',
      doseUnit: pbString(d['dose_unit']),
      doseRate: pbQuantity(d['dose_rate']),
      rateMin: pbQuantity(d['rate_min']),
      rateMax: pbQuantity(d['rate_max']),
      concentrationPerMl: pbQuantity(d['concentration_per_ml']),
      route: pbString(d['route']),
      frequencyKind: MedicationFrequencyKind.fromWire(d['frequency_kind']),
      intervalHours: pbInt(d['interval_hours']),
      note: pbString(d['note']),
      active: pbBool(d['active']),
      org: pbString(d['org']),
      created: pbDate(d['created']),
      updated: pbDate(d['updated']),
    );
  }

  /// Whether [rate] falls outside the catalogue's advisory range. False when no
  /// range is recorded — an unbounded entry cannot judge anything.
  bool isOutOfRange(double rate) =>
      (rateMin != null && rate < rateMin!) ||
      (rateMax != null && rate > rateMax!);

  /// The range as a pair, or null when neither bound is recorded.
  (double? min, double? max)? get range =>
      (rateMin == null && rateMax == null) ? null : (rateMin, rateMax);
}
