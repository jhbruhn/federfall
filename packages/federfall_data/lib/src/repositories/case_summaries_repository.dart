import 'package:federfall_data/src/pb_repository.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:pocketbase/pocketbase.dart';

/// Repository over the org-wide `case_summaries` view (FED-7.6): a
/// clinical-detail-free projection of `cases`, so an animal's whole case
/// history can be listed even when individual cases aren't readable in full.
class PbCaseSummariesRepository extends PbRepository<CaseSummary> {
  PbCaseSummariesRepository(PocketBase pb, {super.cache, super.isOffline})
    : super(
        pb: pb,
        collection: 'case_summaries',
        fromRecord: CaseSummary.fromRecord,
      );

  /// Every case summary for one animal (its admission history), newest first.
  Future<List<CaseSummary>> forAnimal(String animalId) => list(
    filter: filterExpr('animal = {:a}', {'a': animalId}),
    sort: '-created',
  );
}
