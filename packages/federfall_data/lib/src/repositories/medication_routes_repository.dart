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

/// Repository over the `medication_products` catalogue (federfall-6d3a.3): the
/// org's drug protocols, maintained by a supervisor and read by everyone to
/// prefill a prescription.
class PbMedicationProductsRepository extends PbRepository<MedicationProduct> {
  PbMedicationProductsRepository(PocketBase pb)
    : super(
        pb: pb,
        collection: 'medication_products',
        fromRecord: MedicationProduct.fromRecord,
      );

  /// Active entries, label-sorted, for the picker in the prescription form.
  Future<List<MedicationProduct>> active() => list(
    filter: filterExpr('active = true'),
    sort: 'label',
  );

  /// How many catalogue entries still name the [routeId] code-list entry — the
  /// third of the three `medication_routes` referrers.
  Future<int> countForRoute(String routeId) =>
      count(filter: filterExpr('route = {:r}', {'r': routeId}));
}
