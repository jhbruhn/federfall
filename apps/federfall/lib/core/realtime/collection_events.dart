import 'dart:async';

import 'package:federfall/core/connectivity/connectivity.dart';
import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/core/pocketbase/pocketbase_provider.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'collection_events.g.dart';

/// A live stream of PocketBase realtime events for [collection] (topic `*`).
///
/// The building block of the app's live-sync (Pattern A): feature providers
/// listen to this and simply re-fetch their data on a relevant event, so there
/// is one loader (the repositories) with realtime as just another trigger —
/// never a second, hand-merged copy of the list.
///
/// One shared subscription per collection (riverpod de-dupes the family key),
/// multiplexed over PocketBase's single SSE connection. It watches
/// [onlineStatusProvider]: no subscription while offline, and it re-subscribes
/// when connectivity returns. Subscription errors are swallowed — realtime is
/// best-effort and the static loaders stay the source of truth.
@riverpod
Stream<RecordSubscriptionEvent> collectionEvents(
  Ref ref,
  String collection,
) async* {
  if (ref.watch(onlineStatusProvider).value == OnlineStatus.offline) return;

  final pb = await ref.watch(pocketBaseProvider.future);
  final controller = StreamController<RecordSubscriptionEvent>();

  UnsubscribeFunc? unsubscribe;
  try {
    unsubscribe = await pb
        .collection(collection)
        .subscribe('*', controller.add);
  } on Object catch (error, stackTrace) {
    reportCaughtError(error, stackTrace);
    await controller.close();
    return;
  }

  // The provider may have been disposed during the awaits above (e.g.
  // connectivity flipped or the last listener went away). Registering
  // onDispose on a dead ref throws, so tear the subscription down inline.
  if (!ref.mounted) {
    await unsubscribe();
    await controller.close();
    return;
  }

  ref.onDispose(() async {
    await unsubscribe?.call();
    await controller.close();
  });

  yield* controller.stream;
}
