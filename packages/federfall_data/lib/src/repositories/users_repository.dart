import 'package:federfall_data/src/pb_repository.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:pocketbase/pocketbase.dart';

/// Repository over the `users` collection (staff members). Read access is
/// org-scoped by the access rules; used to pick carers for handoffs (FED-4.9).
class PbUsersRepository extends PbRepository<AppUser> {
  PbUsersRepository(PocketBase pb, {super.cache})
    : super(
        pb: pb,
        collection: 'users',
        fromRecord: AppUser.fromRecord,
      );

  /// Active staff members, name-sorted, for assignee/carer pickers.
  Future<List<AppUser>> activeMembers() => list(
    filter: filterExpr('is_active = true'),
    sort: 'name',
  );
}
