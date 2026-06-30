import 'package:federfall_models/src/converters.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:pocketbase/pocketbase.dart';

part 'marking.freezed.dart';

/// A ring, band, microchip or temporary marker carried by an animal. Drives
/// re-identification of returning birds (FED-4.10).
@freezed
abstract class Marking with _$Marking {
  const factory Marking({
    required String id,
    required String animal,

    /// Id into the `marking_types` code list (resolve the label via the
    /// `markingTypesById` provider). Replaces the former inline enum.
    required String type,
    String? code,
    String? schemeOrg,
    String? colour,
    DateTime? appliedAt,
    String? appliedBy,
    String? appliedInCase,
    DateTime? removedAt,
    String? removedReason,
    @Default(false) bool isActive,
    String? org,
    DateTime? created,
    DateTime? updated,
  }) = _Marking;

  factory Marking.fromRecord(RecordModel r) {
    final d = r.data;
    return Marking(
      id: r.id,
      animal: pbString(d['animal']) ?? '',
      type: pbString(d['type']) ?? '',
      code: pbString(d['code']),
      schemeOrg: pbString(d['scheme_org']),
      colour: pbString(d['colour']),
      appliedAt: pbDate(d['applied_at']),
      appliedBy: pbString(d['applied_by']),
      appliedInCase: pbString(d['applied_in_case']),
      removedAt: pbDate(d['removed_at']),
      removedReason: pbString(d['removed_reason']),
      isActive: pbBool(d['is_active']),
      org: pbString(d['org']),
      created: pbDate(d['created']),
      updated: pbDate(d['updated']),
    );
  }
}
