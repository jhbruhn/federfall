import 'dart:async';

import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/case_intake_draft_store.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Asks the user to confirm signing out — one accidental tap must not end the
/// session (and purge the photo cache). Returns whether they confirmed.
Future<bool> confirmSignOut(BuildContext context) async {
  final l10n = context.l10n;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.authSignOutAction),
      content: Text(l10n.authSignOutConfirm),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l10n.actionCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(l10n.authSignOutAction),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Signs the user out and purges the device-local copies of this user's data:
/// the protected-file cache (intake photos, journal attachments, animal photos)
/// and any unfinished intake draft.
///
/// Cache hits are served without any token check, so leaving the store
/// populated would let the next user of this device/browser see the previous
/// user's images — purging restores the server-side protection (FED-8.1). The
/// intake draft goes for the same reason and is arguably worse: it holds the
/// *finder's* contact details (name, phone, email, city) plus the find
/// location, i.e. third-party PII of a member of the public, which the
/// backend's `finder_retention` job exists to minimise server-side. Only
/// `new_case_screen` used to clear it — on a committed intake or an explicit
/// discard — so a carer who backed out mid-wizard and signed out left the next
/// user of the device holding that person's phone number.
///
/// The cost is that signing out mid-intake discards the draft. That is the
/// intended trade: the draft is a convenience, the PII in it is somebody
/// else's.
///
/// Clearing the auth store flips authStatus → the router gate routes back to
/// /login. Both stores are read before any await so the purges still run after
/// the sign-out unmounts the calling screen.
Future<void> signOut(WidgetRef ref) async {
  final cache = ref.read(protectedFileCacheManagerProvider);
  final drafts = ref.read(caseIntakeDraftStoreProvider);
  final repo = await ref.read(authRepositoryProvider.future);
  repo.signOut();
  purgeProtectedFileCache(cache.emptyCache);
  purgeIntakeDraft(drafts.clear);
}

/// Best-effort, fire-and-forget purge of the protected-file cache: a storage
/// error (or a hung store) must never block signing out or switching servers,
/// so the purge runs unawaited and failures are only logged.
void purgeProtectedFileCache(Future<void> Function() emptyCache) =>
    _purge(emptyCache, 'Protected-file cache purge failed');

/// Best-effort, fire-and-forget purge of the unfinished intake draft — same
/// contract as [purgeProtectedFileCache]: a locked keystore must never be what
/// stops someone signing out.
void purgeIntakeDraft(Future<void> Function() clearDraft) =>
    _purge(clearDraft, 'Intake draft purge failed');

void _purge(Future<void> Function() action, String failureContext) {
  unawaited(
    Future(action).catchError((Object error, StackTrace stackTrace) {
      reportCaughtError(error, stackTrace, context: failureContext);
    }),
  );
}
