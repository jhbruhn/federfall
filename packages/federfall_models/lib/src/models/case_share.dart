import 'package:federfall_models/src/converters.dart';
import 'package:federfall_models/src/enums.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:pocketbase/pocketbase.dart';

part 'case_share.freezed.dart';

/// An opt-in grant of read/edit access to one case for one user — the
/// mechanism behind "private by default, shared if desired".
@freezed
abstract class CaseShare with _$CaseShare {
  const factory CaseShare({
    required String id,
    required String caseId,
    required String sharedWith,
    required ShareAccess access,
    String? sharedBy,
    String? org,
    DateTime? created,
    DateTime? updated,
  }) = _CaseShare;

  factory CaseShare.fromRecord(RecordModel r) {
    final d = r.data;
    return CaseShare(
      id: r.id,
      caseId: pbString(d['case']) ?? '',
      sharedWith: pbString(d['shared_with']) ?? '',
      access: ShareAccess.fromWire(d['access']) ?? ShareAccess.read,
      sharedBy: pbString(d['shared_by']),
      org: pbString(d['org']),
      created: pbDate(d['created']),
      updated: pbDate(d['updated']),
    );
  }
}
