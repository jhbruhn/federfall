import 'package:federfall_data/src/pb_repository.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:pocketbase/pocketbase.dart';

/// Repository over the `conditions` code list (supervisor-managed diagnoses).
class PbConditionsRepository extends PbRepository<Condition> {
  PbConditionsRepository(PocketBase pb, {super.cache})
    : super(
        pb: pb,
        collection: 'conditions',
        fromRecord: Condition.fromRecord,
      );

  /// Active code-list entries, label-sorted, for diagnosis pickers.
  Future<List<Condition>> active() => list(
    filter: filterExpr('active = true'),
    sort: 'label',
  );
}

/// Repository over the `case_conditions` collection (diagnoses on a case).
class PbCaseConditionsRepository extends PbRepository<CaseCondition> {
  PbCaseConditionsRepository(PocketBase pb, {super.cache})
    : super(
        pb: pb,
        collection: 'case_conditions',
        fromRecord: CaseCondition.fromRecord,
      );

  /// Diagnoses recorded on a case, newest first.
  Future<List<CaseCondition>> forCase(String caseId) => list(
    filter: filterExpr('case = {:c}', {'c': caseId}),
    sort: '-created',
  );
}
