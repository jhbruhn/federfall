import 'package:federfall_models/src/converters.dart';
import 'package:federfall_models/src/enums.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:pocketbase/pocketbase.dart';

part 'case_report_row.freezed.dart';

/// One line of the annual-report CSV (FED-7.3), read pre-joined from the
/// `case_report_rows` view (federfall-80tc): a case with its animal's
/// species/name, its terminal outcome and the labels of its admission reasons.
///
/// The view does the join server-side so the export reads one small row set
/// instead of pulling `cases`, `dispositions` and `animals` whole to the
/// device. It is coordinator/supervisor-scoped and org-wide by construction —
/// see the migration for why.
///
/// Values stay structured (enums, dates, DB-authored labels) and unlocalized;
/// the export formats them, mirroring how the PDF hook leaves translation to
/// its templates.
@freezed
abstract class CaseReportRow with _$CaseReportRow {
  const factory CaseReportRow({
    required String id,
    String? caseNumber,
    @Default('') String species,
    String? name,
    DateTime? admittedAt,
    DateTime? foundAt,
    CaseStatus? status,
    DispositionType? outcome,
    DateTime? endedAt,
    String? city,
    String? region,

    /// The case's admission-reason labels, already resolved and joined by the
    /// view ("Verletzung; Katzenangriff"). Empty when none were recorded.
    @Default('') String reasons,
    String? org,
  }) = _CaseReportRow;

  const CaseReportRow._();

  factory CaseReportRow.fromRecord(RecordModel r) {
    final d = r.data;
    return CaseReportRow(
      id: r.id,
      caseNumber: pbString(d['case_number']),
      species: pbString(d['species']) ?? '',
      name: pbString(d['name']),
      admittedAt: pbDate(d['admitted_at']),
      foundAt: pbDate(d['found_at']),
      status: CaseStatus.fromWire(d['status']),
      outcome: DispositionType.fromWire(d['outcome']),
      endedAt: pbDate(d['ended_at']),
      city: pbString(d['city']),
      region: pbString(d['region']),
      reasons: pbString(d['reasons']) ?? '',
      org: pbString(d['org']),
    );
  }

  /// Days from admission to the terminal disposition, or null when the case is
  /// still open or the two dates don't span forwards. Derived here rather than
  /// in the view: it is a subtraction per row, and keeping it in Dart keeps the
  /// arithmetic (and its test) where the CSV is written.
  int? get daysInCare {
    final admitted = admittedAt;
    final ended = endedAt;
    if (admitted == null || ended == null || ended.isBefore(admitted)) {
      return null;
    }
    return ended.difference(admitted).inDays;
  }
}
