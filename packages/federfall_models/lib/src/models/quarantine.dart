import 'package:federfall_models/src/converters.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:pocketbase/pocketbase.dart';

part 'quarantine.freezed.dart';

/// One quarantine period on a case (federfall-uvm) — a timeline record like a
/// weight or condition rather than a field on the case. [setAt] is when the
/// quarantine was imposed (its place on the chronology); [until] is when it
/// ends. Extending or lifting quarantine adds or edits a row; the current end
/// is the latest row (see [CaseQuarantine]).
@freezed
abstract class Quarantine with _$Quarantine {
  const factory Quarantine({
    required String id,
    required String caseId,
    DateTime? setAt,
    DateTime? until,
    String? reason,
    String? setBy,
    String? org,
    DateTime? created,
    DateTime? updated,
  }) = _Quarantine;

  factory Quarantine.fromRecord(RecordModel r) {
    final d = r.data;
    return Quarantine(
      id: r.id,
      caseId: pbString(d['case']) ?? '',
      setAt: pbDate(d['set_at']),
      until: pbDate(d['quarantine_until']),
      reason: pbString(d['reason']),
      setBy: pbString(d['set_by']),
      org: pbString(d['org']),
      created: pbDate(d['created']),
      updated: pbDate(d['updated']),
    );
  }
}

/// The current quarantine end per case, read from the org-wide
/// `case_quarantine` view (federfall-uvm): the latest [Quarantine] row's
/// [until], so the worklist and dashboard read quarantine state in one query
/// instead of the dropped `cases.quarantine_until` mirror. The record [id] is
/// the case id.
@freezed
abstract class CaseQuarantine with _$CaseQuarantine {
  const factory CaseQuarantine({
    required String id,
    DateTime? until,
    DateTime? setAt,
    String? org,
  }) = _CaseQuarantine;

  factory CaseQuarantine.fromRecord(RecordModel r) {
    final d = r.data;
    return CaseQuarantine(
      id: r.id,
      until: pbDate(d['quarantine_until']),
      setAt: pbDate(d['set_at']),
      org: pbString(d['org']),
    );
  }
}
