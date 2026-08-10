import 'package:federfall_data/src/pb_repository.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:pocketbase/pocketbase.dart';

/// Repository over the `case_shares` collection (opt-in access grants).
class PbCaseSharesRepository extends PbRepository<CaseShare> {
  PbCaseSharesRepository(PocketBase pb)
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

  /// Every `edit` share held by [userId], across all cases — the share branch
  /// of the custody predicate (1700000077), in ONE request.
  ///
  /// Asked user-wide rather than per case on purpose: custody has to be
  /// answered for a bird whose cases the asker may not be able to read at all,
  /// and a per-case lookup would put one request per case into a screen that
  /// already has the animal's whole history (federfall-trep). The read rule
  /// scopes this to the user's own shares, so it stays as small as their
  /// caseload.
  Future<List<CaseShare>> editSharedWith(String userId) => list(
    filter: filterExpr('shared_with = {:u} && access = {:a}', {
      'u': userId,
      'a': ShareAccess.edit.wire,
    }),
  );
}
