import 'package:federfall_data/src/pb_repository.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:pocketbase/pocketbase.dart';

/// Repository over the `dispositions` collection (case outcomes).
class PbDispositionsRepository extends PbRepository<Disposition> {
  PbDispositionsRepository(PocketBase pb)
      : super(
          pb: pb,
          collection: 'dispositions',
          fromRecord: Disposition.fromRecord,
        );

  /// Disposition history for a case, newest first (usually one final row).
  Future<List<Disposition>> forCase(String caseId) => list(
        filter: filterExpr('case = {:c}', {'c': caseId}),
        sort: '-disposed_at',
      );
}
