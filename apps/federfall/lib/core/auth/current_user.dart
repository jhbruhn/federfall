import 'package:federfall/data/repository_providers.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'current_user.g.dart';

/// The currently authenticated [AppUser], or `null` when signed out.
///
/// Re-evaluated on every auth change (login/logout/refresh) so the UI — the
/// home shell now, role-gated nav in FED-3.3 — reacts to the session. This is
/// the *identity* counterpart to `authStatusProvider`, which only answers the
/// boolean the router gate needs.
@Riverpod(keepAlive: true)
Future<AppUser?> currentUser(Ref ref) async {
  final repo = await ref.watch(authRepositoryProvider.future);

  final sub = repo.changes.listen((_) => ref.invalidateSelf());
  ref.onDispose(sub.cancel);

  return repo.currentUser;
}
