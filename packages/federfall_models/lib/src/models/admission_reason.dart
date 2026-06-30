import 'package:federfall_models/src/converters.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:pocketbase/pocketbase.dart';

part 'admission_reason.freezed.dart';

/// A supervisor-managed code-list entry (a reason a bird was admitted). Cases
/// reference these via the multi-relation `cases.admission_reasons`; the
/// vocabulary is editable at runtime, like the `conditions` code list.
@freezed
abstract class AdmissionReason with _$AdmissionReason {
  const factory AdmissionReason({
    required String id,
    required String label,
    @Default(true) bool active,
    String? org,
    DateTime? created,
    DateTime? updated,
  }) = _AdmissionReason;

  factory AdmissionReason.fromRecord(RecordModel r) {
    final d = r.data;
    return AdmissionReason(
      id: r.id,
      label: pbString(d['label']) ?? '',
      active: pbBool(d['active']),
      org: pbString(d['org']),
      created: pbDate(d['created']),
      updated: pbDate(d['updated']),
    );
  }
}
