import 'package:federfall_data/src/pb_repository.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:pocketbase/pocketbase.dart';

/// Repository over the `condition_labels` view: the distinct diagnoses the org
/// has actually recorded, with the number of cases carrying each
/// (federfall-ye5e).
///
/// The server decides how much of this a caller sees — free-text labels reach
/// coordinators and supervisors only — so a short list is a legitimate answer,
/// not a partial read.
class PbConditionLabelsRepository extends PbReadOnlyRepository<ConditionLabel> {
  PbConditionLabelsRepository(PocketBase pb)
    : super(
        pb: pb,
        collection: 'condition_labels',
        fromRecord: ConditionLabel.fromRecord,
      );

  /// Every recorded diagnosis, most-used first then alphabetical — free text
  /// does not normalise ("Katzenbiss" and "katzenbiss" stay separate), so
  /// leading with frequency puts the ones that matter on top.
  Future<List<ConditionLabel>> all() => list(sort: '-case_count,label');
}
