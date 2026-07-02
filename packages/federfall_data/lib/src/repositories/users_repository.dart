import 'package:federfall_data/src/pb_repository.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:pocketbase/pocketbase.dart';

/// Repository over the `users` collection (staff members). Read access is
/// org-scoped by the access rules; used to pick carers for handoffs (FED-4.9).
class PbUsersRepository extends PbRepository<AppUser> {
  PbUsersRepository(PocketBase pb)
    : super(
        pb: pb,
        collection: 'users',
        fromRecord: AppUser.fromRecord,
      );

  /// Active staff members, name-sorted, for assignee/carer pickers. Guests are
  /// excluded: the access rules wall them off from all case data, so sharing
  /// with or handing off to a guest would silently grant nothing (and make the
  /// case invisible to its own active carer).
  Future<List<AppUser>> activeMembers() => list(
    filter: filterExpr('is_active = true && role != {:guest}', {
      'guest': UserRole.guest.wire,
    }),
    sort: 'name',
  );

  /// Every staff member (active and not), active first then name-sorted, for
  /// the supervisor's team roster (UX Phase A).
  Future<List<AppUser>> members() => list(sort: '-is_active,name');
}
