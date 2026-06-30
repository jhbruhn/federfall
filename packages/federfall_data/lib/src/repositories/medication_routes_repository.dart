import 'package:federfall_data/src/pb_repository.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:pocketbase/pocketbase.dart';

/// Repository over the `medication_routes` code list (supervisor-managed routes
/// of administration: oral, subcutaneous…).
class PbMedicationRoutesRepository extends PbRepository<MedicationRoute> {
  PbMedicationRoutesRepository(PocketBase pb)
    : super(
        pb: pb,
        collection: 'medication_routes',
        fromRecord: MedicationRoute.fromRecord,
      );

  /// Active code-list entries, label-sorted, for the route picker.
  Future<List<MedicationRoute>> active() => list(
    filter: filterExpr('active = true'),
    sort: 'label',
  );
}
