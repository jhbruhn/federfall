import 'package:federfall_data/src/pb_repository.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:pocketbase/pocketbase.dart';

/// Repository over the `admission_reasons` code list (supervisor-managed
/// reasons a bird was admitted).
class PbAdmissionReasonsRepository extends PbRepository<AdmissionReason> {
  PbAdmissionReasonsRepository(PocketBase pb)
    : super(
        pb: pb,
        collection: 'admission_reasons',
        fromRecord: AdmissionReason.fromRecord,
      );

  /// Active code-list entries, label-sorted, for the admission-reason picker.
  Future<List<AdmissionReason>> active() => list(
    filter: filterExpr('active = true'),
    sort: 'label',
  );
}
