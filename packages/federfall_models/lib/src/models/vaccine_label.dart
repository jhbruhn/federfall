import 'package:federfall_models/src/converters.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:pocketbase/pocketbase.dart';

part 'vaccine_label.freezed.dart';

/// One (vaccine, target) pair this org has actually recorded, read from the
/// `vaccine_labels` view (1700000088).
///
/// The vocabulary behind `vaccinations`' free-text fields — the same answer
/// `animal_species` and `condition_labels` give: a list built out of use, so it
/// offers nothing dead and needs no seeding. The pair is one row on purpose,
/// which is what lets picking a product prefill the target it was recorded
/// against.
///
/// Nothing is normalised: "PMV" and "Paramyxovirose" are two rows, because the
/// view reports what was written rather than guessing. [useCount] and
/// [lastUsedAt] exist so suggestions can rank by what this org reaches for
/// rather than alphabetically.
@freezed
abstract class VaccineLabel with _$VaccineLabel {
  const factory VaccineLabel({
    required String id,
    required String vaccine,
    String? target,
    @Default(0) int useCount,
    DateTime? lastUsedAt,
    String? org,
  }) = _VaccineLabel;

  factory VaccineLabel.fromRecord(RecordModel r) {
    final d = r.data;
    return VaccineLabel(
      id: r.id,
      vaccine: pbString(d['vaccine']) ?? '',
      target: pbString(d['target']),
      useCount: pbInt(d['use_count']) ?? 0,
      lastUsedAt: pbDate(d['last_used_at']),
      org: pbString(d['org']),
    );
  }
}
