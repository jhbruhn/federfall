import 'package:federfall_data/src/pb_repository.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:pocketbase/pocketbase.dart';

/// Repository over the `case_report_rows` view: the annual-report CSV
/// (FED-7.3) pre-joined server-side, one row per case (federfall-80tc).
///
/// The view is coordinator/supervisor-only, so a carer legitimately reads
/// nothing here — the export that uses it is `canViewReports`-gated for the
/// same reason.
class PbCaseReportRowsRepository extends PbReadOnlyRepository<CaseReportRow> {
  PbCaseReportRowsRepository(PocketBase pb)
    : super(
        pb: pb,
        collection: 'case_report_rows',
        fromRecord: CaseReportRow.fromRecord,
      );

  /// Every reportable case, newest admission first. Cases with no admission
  /// date land at the end: PocketBase stores an unset date as the empty
  /// string, which sorts last descending — the order the client-side join used
  /// to produce explicitly.
  Future<List<CaseReportRow>> all() => list(sort: '-admitted_at');
}
