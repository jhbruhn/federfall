import 'package:federfall_data/src/pb_repository.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:pocketbase/pocketbase.dart';

/// Repository over the org-wide `case_activity` view (cr3.5): the last time
/// anything happened on each case, used to surface "stale" cases on the carer
/// worklist without an N+1 scan of every child collection.
class PbCaseLastActivityRepository
    extends PbReadOnlyRepository<CaseLastActivity> {
  PbCaseLastActivityRepository(PocketBase pb)
    : super(
        pb: pb,
        collection: 'case_activity',
        fromRecord: CaseLastActivity.fromRecord,
      );

  /// Activity for every case the signed-in member may see (org-scoped).
  Future<List<CaseLastActivity>> all() => list(sort: '-last_activity');
}
