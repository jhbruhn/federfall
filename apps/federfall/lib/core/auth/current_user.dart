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
///
/// **Watch a field, not the object** (federfall-bpw6). "Every auth change"
/// includes a token *refresh*, which `sessionRefresh` performs on
/// `AppLifecycleListener.onResume` — on web that is every time the window
/// regains focus. `ref.watch(currentUserProvider.future)` hands out a new
/// future each time, so a dependent recomputes in full even though nothing
/// about the user changed; that is how refocusing a browser tab came to
/// refetch the whole case list. Depend on what you actually use instead:
///
/// ```dart
/// final me = await ref.watch(currentUserProvider.selectAsync((u) => u?.id));
/// ```
///
/// A refresh then yields the same selected value and nothing downstream
/// reruns. [AppUser] is `freezed`, so selecting the whole object works too
/// where a caller genuinely needs all of it — value equality does the
/// deduplication. `ref.read` is unaffected: it never subscribes.
@Riverpod(keepAlive: true)
Future<AppUser?> currentUser(Ref ref) async {
  final repo = await ref.watch(authRepositoryProvider.future);

  final sub = repo.changes.listen((_) => ref.invalidateSelf());
  // Disposed during the await above? onDispose would throw; cancel inline.
  if (!ref.mounted) {
    await sub.cancel();
    return repo.currentUser;
  }
  ref.onDispose(sub.cancel);

  return repo.currentUser;
}
