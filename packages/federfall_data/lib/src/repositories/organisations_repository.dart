import 'package:federfall_data/src/pb_repository.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:pocketbase/pocketbase.dart';

/// Repository over the `organisations` collection. A member can read their own
/// org; only a supervisor can update it (enforced server-side). Create/delete
/// are superuser-only — there is a single launch org.
class PbOrganisationsRepository extends PbRepository<Organisation> {
  PbOrganisationsRepository(PocketBase pb, {super.cache, super.isOffline})
    : super(
        pb: pb,
        collection: 'organisations',
        fromRecord: Organisation.fromRecord,
      );
}
