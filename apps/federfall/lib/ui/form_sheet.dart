import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zugvogel_ui/zugvogel_ui.dart';

// The busy/error lifecycle, the form key, runSave and the sheet shell moved to
// zugvogel_ui (eiermann-d2a.9) — every create/edit sheet in either app repeats
// the same try/catch tail and the same padding/scroll/title/error/save layout.
//
// requireUserOrg did NOT move, and could not: resolving "the signed-in user
// and their organisation" needs federfall's own AppUser and its
// currentUserProvider, and a shared package that knew either would know this
// app's data model. It stays here as an extension on the library's mixin, so
// the ~20 sheets that call it keep writing `with FormSheetState<...>` and
// `await requireUserOrg()` exactly as before.
export 'package:zugvogel_ui/zugvogel_ui.dart'
    show FormSheetState, SheetScaffold, trimToNull;

/// The org guard every write in this app runs first.
///
/// An extension rather than a member of a federfall mixin so no sheet has to
/// name two mixins: the method resolves on the library's [FormSheetState] the
/// same way it did when it lived inside it.
extension FormSheetOrgGuard<T extends ConsumerStatefulWidget>
    on FormSheetState<T> {
  /// Resolves the signed-in user and their org, or fails with the
  /// [RepositoryException] every sheet throws before writing without one.
  Future<(AppUser user, String org)> requireUserOrg() async {
    final user = await ref.read(currentUserProvider.future);
    final org = user?.org;
    if (user == null || org == null) {
      throw const RepositoryException('no org for current user');
    }
    return (user, org);
  }
}
