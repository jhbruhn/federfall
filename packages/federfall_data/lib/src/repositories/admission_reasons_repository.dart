import 'package:federfall_data/src/pb_repository.dart';
import 'package:federfall_data/src/repositories/codelist_repository.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:pocketbase/pocketbase.dart';

/// Repository over the `admission_reasons` code list (supervisor-managed
/// reasons a bird was admitted).
class PbAdmissionReasonsRepository extends PbRepository<AdmissionReason>
    with CodelistRepository<AdmissionReason> {
  PbAdmissionReasonsRepository(PocketBase pb)
    : super(
        pb: pb,
        collection: 'admission_reasons',
        fromRecord: AdmissionReason.fromRecord,
      );

  @override
  String labelOf(AdmissionReason entry) => entry.label;
}
