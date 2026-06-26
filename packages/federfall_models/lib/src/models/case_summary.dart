import 'package:federfall_models/src/converters.dart';
import 'package:federfall_models/src/enums.dart';
import 'package:federfall_models/src/models/medical_case.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:pocketbase/pocketbase.dart';

part 'case_summary.freezed.dart';

/// A clinical-detail-free summary of a [Case], read from the org-wide
/// `case_summaries` view (FED-7.6). Used by the animal lifetime record to list
/// every case — including ones the user cannot fully open, which render as a
/// non-tappable stub from just these fields.
@freezed
abstract class CaseSummary with _$CaseSummary {
  const factory CaseSummary({
    required String id,
    required String animal,
    String? caseNumber,
    CaseStatus? status,
    DateTime? admittedAt,
    DateTime? foundAt,
    DateTime? endedAt,
    String? org,
    String? activeCarer,
    DateTime? created,
  }) = _CaseSummary;

  factory CaseSummary.fromRecord(RecordModel r) {
    final d = r.data;
    return CaseSummary(
      id: r.id,
      animal: pbString(d['animal']) ?? '',
      caseNumber: pbString(d['case_number']),
      status: CaseStatus.fromWire(d['status']),
      admittedAt: pbDate(d['admitted_at']),
      foundAt: pbDate(d['found_at']),
      endedAt: pbDate(d['ended_at']),
      org: pbString(d['org']),
      activeCarer: pbString(d['active_carer']),
      created: pbDate(d['created']),
    );
  }
}
