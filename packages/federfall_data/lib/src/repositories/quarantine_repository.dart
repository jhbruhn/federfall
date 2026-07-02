import 'package:federfall_data/src/pb_repository.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:pocketbase/pocketbase.dart';

/// Repository over the `quarantine_records` collection (federfall-uvm): the
/// quarantine timeline on a case. The default 14-day intake row is created
/// server-side by the cases hook.
class PbQuarantineRepository extends PbRepository<Quarantine> {
  PbQuarantineRepository(PocketBase pb)
    : super(
        pb: pb,
        collection: 'quarantine_records',
        fromRecord: Quarantine.fromRecord,
      );

  /// Quarantine records for a case, newest first.
  Future<List<Quarantine>> forCase(String caseId) => list(
    filter: filterExpr('case = {:c}', {'c': caseId}),
    sort: '-created',
  );
}

/// Repository over the org-wide `case_quarantine` view (federfall-uvm): the
/// current quarantine end per case (the latest record), the worklist's and
/// dashboard's quarantine source — one query instead of a per-case scan.
class PbCaseQuarantineRepository extends PbReadOnlyRepository<CaseQuarantine> {
  PbCaseQuarantineRepository(PocketBase pb)
    : super(
        pb: pb,
        collection: 'case_quarantine',
        fromRecord: CaseQuarantine.fromRecord,
      );

  /// Current quarantine end for every case the member may see (org-scoped).
  Future<List<CaseQuarantine>> all() => list();
}
