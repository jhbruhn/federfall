import 'package:federfall_data/src/pb_repository.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:pocketbase/pocketbase.dart';

/// Repository over the `aviaries` collection (permanent-care enclosures).
class PbAviariesRepository extends PbRepository<Aviary> {
  PbAviariesRepository(PocketBase pb, {super.cache, super.isOffline})
    : super(
        pb: pb,
        collection: 'aviaries',
        fromRecord: Aviary.fromRecord,
      );

  /// Active aviaries, name-sorted, for pickers and the aviary list.
  Future<List<Aviary>> active() => list(
    filter: filterExpr('active = true'),
    sort: 'name',
  );
}
