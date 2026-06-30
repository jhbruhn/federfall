import 'package:federfall_models/src/converters.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:pocketbase/pocketbase.dart';

part 'marking_type.freezed.dart';

/// A supervisor-managed code-list entry (a kind of marking: ring, microchip,
/// temporary marker…). Markings reference one via the `markings.type` relation;
/// the vocabulary is editable at runtime, like the `conditions` code list.
@freezed
abstract class MarkingType with _$MarkingType {
  const factory MarkingType({
    required String id,
    required String label,
    @Default(true) bool active,
    String? org,
    DateTime? created,
    DateTime? updated,
  }) = _MarkingType;

  factory MarkingType.fromRecord(RecordModel r) {
    final d = r.data;
    return MarkingType(
      id: r.id,
      label: pbString(d['label']) ?? '',
      active: pbBool(d['active']),
      org: pbString(d['org']),
      created: pbDate(d['created']),
      updated: pbDate(d['updated']),
    );
  }
}
