import 'package:federfall_data/src/pb_repository.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:pocketbase/pocketbase.dart';

/// Repository over the `aviary_stays` collection (append-only residency
/// ledger, federfall-d5co.1). Read-only from the app: rows are maintained
/// server-side by a hook on `animals`, never written directly by a client.
class PbAviaryStaysRepository extends PbReadOnlyRepository<AviaryStay> {
  PbAviaryStaysRepository(PocketBase pb)
    : super(
        pb: pb,
        collection: 'aviary_stays',
        fromRecord: AviaryStay.fromRecord,
      );

  /// Residency history for an aviary, newest stay first.
  Future<List<AviaryStay>> forAviary(String aviaryId) => list(
    filter: filterExpr('aviary = {:a}', {'a': aviaryId}),
    sort: '-started_at',
  );
}
