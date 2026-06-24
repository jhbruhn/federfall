import 'package:federfall_models/src/converters.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:pocketbase/pocketbase.dart';

part 'case_activity.freezed.dart';

/// The last time anything happened on a case, read from the org-wide
/// `case_activity` view (cr3.5). `lastActivity` is the newest `updated` across
/// the case and all its child records. The record [id] is the case id. Powers
/// the worklist's "stale cases" source.
@freezed
abstract class CaseLastActivity with _$CaseLastActivity {
  const factory CaseLastActivity({
    required String id,
    DateTime? lastActivity,
    String? org,
  }) = _CaseLastActivity;

  factory CaseLastActivity.fromRecord(RecordModel r) {
    final d = r.data;
    return CaseLastActivity(
      id: r.id,
      lastActivity: pbDate(d['last_activity']),
      org: pbString(d['org']),
    );
  }
}
