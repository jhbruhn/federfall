import 'package:federfall_data/src/pb_repository.dart';
import 'package:federfall_data/src/repositories/codelist_repository.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:pocketbase/pocketbase.dart';

/// Repository over the `marking_types` code list (supervisor-managed kinds of
/// marking: ring, microchip, temporary marker…).
class PbMarkingTypesRepository extends PbRepository<MarkingType>
    with CodelistRepository<MarkingType> {
  PbMarkingTypesRepository(PocketBase pb)
    : super(
        pb: pb,
        collection: 'marking_types',
        fromRecord: MarkingType.fromRecord,
      );

  @override
  String labelOf(MarkingType entry) => entry.label;
}
