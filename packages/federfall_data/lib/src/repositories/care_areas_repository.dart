import 'package:federfall_data/src/pb_repository.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:pocketbase/pocketbase.dart';

/// Repository over the `care_areas` collection: the rooms a carer houses
/// their birds in (federfall-r67n).
///
/// Org-readable, owner-writable — the access rules pin `owner` to the caller
/// on create and freeze it, so a create body must name the caller.
class PbCareAreasRepository extends PbRepository<CareArea> {
  PbCareAreasRepository(PocketBase pb)
    : super(
        pb: pb,
        collection: 'care_areas',
        fromRecord: CareArea.fromRecord,
      );

  /// Every area the caller may read, in each owner's own order. Small by
  /// nature — a handful of rooms per carer — so it is read whole and cached.
  Future<List<CareArea>> all() => list(sort: 'owner,position,name');
}
