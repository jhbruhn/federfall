import 'package:federfall_data/src/pb_repository.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:pocketbase/pocketbase.dart';

/// Repository over the `case_shares` collection (opt-in access grants).
class PbCaseSharesRepository extends PbRepository<CaseShare> {
  PbCaseSharesRepository(PocketBase pb, {super.cache, super.isOffline})
    : super(
        pb: pb,
        collection: 'case_shares',
        fromRecord: CaseShare.fromRecord,
      );

  /// Shares granted on a case, expanding the target user for display.
  Future<List<CaseShare>> forCase(String caseId) => list(
    filter: filterExpr('case = {:c}', {'c': caseId}),
    expand: 'shared_with',
  );
}
