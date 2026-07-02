import 'dart:async';

import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Signs the user out and purges the on-device protected-file cache (intake
/// photos, journal attachments, animal photos). Cache hits are served without
/// any token check, so leaving the store populated would let the next user of
/// this device/browser see the previous user's images — purging restores the
/// server-side protection (FED-8.1).
///
/// Clearing the auth store flips authStatus → the router gate routes back to
/// /login. The cache manager is read before any await so the purge still runs
/// after the sign-out unmounts the calling screen.
Future<void> signOut(WidgetRef ref) async {
  final cache = ref.read(protectedFileCacheManagerProvider);
  final repo = await ref.read(authRepositoryProvider.future);
  repo.signOut();
  purgeProtectedFileCache(cache.emptyCache);
}

/// Best-effort, fire-and-forget purge of the protected-file cache: a storage
/// error (or a hung store) must never block signing out or switching servers,
/// so the purge runs unawaited and failures are only logged.
void purgeProtectedFileCache(Future<void> Function() emptyCache) {
  unawaited(
    Future(emptyCache).catchError((Object error, StackTrace stackTrace) {
      reportCaughtError(
        error,
        stackTrace,
        context: 'Protected-file cache purge failed',
      );
    }),
  );
}
