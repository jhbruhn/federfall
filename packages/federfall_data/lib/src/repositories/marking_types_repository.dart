import 'package:federfall_data/src/pb_repository.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:pocketbase/pocketbase.dart';

/// Repository over the `marking_types` code list (supervisor-managed kinds of
/// marking: ring, microchip, temporary marker…).
class PbMarkingTypesRepository extends PbRepository<MarkingType> {
  PbMarkingTypesRepository(PocketBase pb)
    : super(
        pb: pb,
        collection: 'marking_types',
        fromRecord: MarkingType.fromRecord,
      );

  /// Active code-list entries, label-sorted, for the marking-type picker.
  Future<List<MarkingType>> active() => list(
    filter: filterExpr('active = true'),
    sort: 'label',
  );
}
