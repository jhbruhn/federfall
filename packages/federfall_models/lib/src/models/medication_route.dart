import 'package:federfall_models/src/converters.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:pocketbase/pocketbase.dart';

part 'medication_route.freezed.dart';

/// A supervisor-managed code-list entry (a route of administration: oral,
/// subcutaneous…). Medications and administrations reference one via their
/// `route` relation; the vocabulary is editable at runtime, like the
/// `conditions` code list.
@freezed
abstract class MedicationRoute with _$MedicationRoute {
  const factory MedicationRoute({
    required String id,
    required String label,
    @Default(true) bool active,
    String? org,
    DateTime? created,
    DateTime? updated,
  }) = _MedicationRoute;

  factory MedicationRoute.fromRecord(RecordModel r) {
    final d = r.data;
    return MedicationRoute(
      id: r.id,
      label: pbString(d['label']) ?? '',
      active: pbBool(d['active']),
      org: pbString(d['org']),
      created: pbDate(d['created']),
      updated: pbDate(d['updated']),
    );
  }
}
