import 'package:federfall_models/src/converters.dart';
import 'package:federfall_models/src/enums.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:pocketbase/pocketbase.dart';

part 'egg_record.freezed.dart';

/// One egg-laying event on an animal (federfall-4agw).
///
/// A longitudinal property of the ANIMAL, not of a case — there is deliberately
/// no `case` field. Timeline membership is computed from the animal (the stance
/// `Marking` takes), so re-attributing an egg to another bird is a single write
/// to [animal] and the row moves between case timelines on its own.
///
/// A clutch is derived from the dates, never stored: consecutive events closer
/// together than the client's clutch gap belong to one clutch. [laidAt] is
/// optional in the schema and falls back to [created], the way
/// `weights.measured_at` does.
@freezed
abstract class EggRecord with _$EggRecord {
  const factory EggRecord({
    required String id,
    required String animal,

    /// Eggs in this one laying event. Usually 1; covers "found 2, exact dates
    /// unknown" without inventing dates.
    @Default(1) int count,
    DateTime? laidAt,
    EggFertility? fertility,
    EggFate? fate,
    @Default(EggAttribution.confirmed) EggAttribution attribution,

    /// Up to three photos, e.g. documenting an abnormal egg (a Windei).
    @Default(<String>[]) List<String> photos,
    String? notes,
    String? author,
    String? org,
    DateTime? created,
    DateTime? updated,
  }) = _EggRecord;

  factory EggRecord.fromRecord(RecordModel r) {
    final d = r.data;
    return EggRecord(
      id: r.id,
      animal: pbString(d['animal']) ?? '',
      // A missing or garbage count still means at least one egg was found.
      count: pbInt(d['count']) ?? 1,
      laidAt: pbDate(d['laid_at']),
      fertility: EggFertility.fromWire(d['fertility']),
      fate: EggFate.fromWire(d['fate']),
      attribution:
          EggAttribution.fromWire(d['attribution']) ?? EggAttribution.confirmed,
      photos: pbStringList(d['photos']),
      notes: pbString(d['notes']),
      author: pbString(d['author']),
      org: pbString(d['org']),
      created: pbDate(d['created']),
      updated: pbDate(d['updated']),
    );
  }
}
