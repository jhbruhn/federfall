import 'package:federfall_data/src/pb_repository.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:pocketbase/pocketbase.dart';

/// Repository over the `finders` collection (external rescuer PII).
class PbFindersRepository extends PbRepository<Finder> {
  PbFindersRepository(PocketBase pb, {super.cache, super.isOffline})
    : super(
        pb: pb,
        collection: 'finders',
        fromRecord: Finder.fromRecord,
      );

  /// Finders matching [query] across name/phone/email, for intake lookup.
  Future<List<Finder>> search(String query) => list(
    filter: filterExpr(
      'last_name ~ {:q} || first_name ~ {:q} || phone ~ {:q} '
      '|| email ~ {:q}',
      {'q': query},
    ),
    sort: 'last_name',
  );
}
