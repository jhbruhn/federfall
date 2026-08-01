import 'package:federfall_models/src/converters.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:pocketbase/pocketbase.dart';

part 'condition_label.freezed.dart';

/// One diagnosis the org has actually recorded, read from the `condition_labels`
/// view (federfall-ye5e): its display [label] and the number of cases carrying
/// it.
///
/// A `case_conditions` row is either a `conditions` code-list reference or its
/// own free text, so the view groups on the resolved label — which is why this
/// is keyed by a string and not by [condition]. That id is empty exactly when
/// the label exists only as free text; the view's access rule uses it to keep
/// those rows away from members who cannot read the cases they were typed on,
/// so a carer simply receives fewer rows than a coordinator.
@freezed
abstract class ConditionLabel with _$ConditionLabel {
  const factory ConditionLabel({
    required String id,
    required String label,
    @Default(0) int caseCount,

    /// The code-list entry behind [label], or null when it is free text only.
    String? condition,
    String? org,
  }) = _ConditionLabel;

  factory ConditionLabel.fromRecord(RecordModel r) {
    final d = r.data;
    return ConditionLabel(
      id: r.id,
      label: pbString(d['label']) ?? '',
      caseCount: pbInt(d['case_count']) ?? 0,
      condition: pbString(d['condition']),
      org: pbString(d['org']),
    );
  }
}
