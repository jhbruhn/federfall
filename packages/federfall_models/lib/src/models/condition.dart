import 'package:federfall_models/src/converters.dart';
import 'package:federfall_models/src/enums.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:pocketbase/pocketbase.dart';

part 'condition.freezed.dart';

/// A supervisor-managed code-list entry (a diagnosis/condition name).
@freezed
abstract class Condition with _$Condition {
  const factory Condition({
    required String id,
    required String label,
    @Default(false) bool isNotifiable,
    @Default(false) bool isContagious,
    String? description,
    @Default(true) bool active,
    String? org,
    DateTime? created,
    DateTime? updated,
  }) = _Condition;

  factory Condition.fromRecord(RecordModel r) {
    final d = r.data;
    return Condition(
      id: r.id,
      label: pbString(d['label']) ?? '',
      isNotifiable: pbBool(d['is_notifiable']),
      isContagious: pbBool(d['is_contagious']),
      description: pbString(d['description']),
      active: pbBool(d['active']),
      org: pbString(d['org']),
      created: pbDate(d['created']),
      updated: pbDate(d['updated']),
    );
  }
}

/// A diagnosis recorded on a case — either a [Condition] code-list reference or
/// free text.
@freezed
abstract class CaseCondition with _$CaseCondition {
  const factory CaseCondition({
    required String id,
    required String caseId,
    String? condition,
    String? freeText,
    Certainty? certainty,
    DateTime? onsetDate,
    DateTime? resolvedDate,
    String? notes,
    String? org,
    DateTime? created,
    DateTime? updated,
  }) = _CaseCondition;

  factory CaseCondition.fromRecord(RecordModel r) {
    final d = r.data;
    return CaseCondition(
      id: r.id,
      caseId: pbString(d['case']) ?? '',
      condition: pbString(d['condition']),
      freeText: pbString(d['free_text']),
      certainty: Certainty.fromWire(d['certainty']),
      onsetDate: pbDate(d['onset_date']),
      resolvedDate: pbDate(d['resolved_date']),
      notes: pbString(d['notes']),
      org: pbString(d['org']),
      created: pbDate(d['created']),
      updated: pbDate(d['updated']),
    );
  }
}
