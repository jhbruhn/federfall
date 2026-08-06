import 'package:federfall_data/src/pb_repository.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:pocketbase/pocketbase.dart';

/// Repository over the `case_carer_load` view (federfall-s0wk): every team
/// member's open (non-disposed) caseload in the caller's org, counted
/// server-side rather than by tallying a downloaded case list.
///
/// The view's list rule admits coordinators and supervisors only. A list
/// request applies that rule as a filter, so a carer gets an **empty list**,
/// not an error — the same answer the workload card already shows them, since
/// it gates on `canViewReports`. Callers must therefore treat "no rows" as a
/// legitimate result rather than a failed read.
class PbCarerLoadRepository extends PbReadOnlyRepository<CarerCaseLoad> {
  PbCarerLoadRepository(PocketBase pb)
    : super(
        pb: pb,
        collection: 'case_carer_load',
        fromRecord: CarerCaseLoad.fromRecord,
      );

  /// Every carer's open caseload the caller may read — one row per carer,
  /// unsorted (the dashboard orders them by load and then by name, which needs
  /// the roster this view does not carry).
  Future<List<CarerCaseLoad>> all() => list();
}
