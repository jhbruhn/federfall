import 'package:federfall/core/connectivity/connectivity.dart';
import 'package:federfall/core/realtime/collection_events.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Live-sync helper for browse/summary screens (Pattern A).
extension LiveRefresh on WidgetRef {
  /// Calls [onChange] whenever any of [collections] emits a realtime event, and
  /// once when connectivity is regained (to catch up on anything missed while
  /// offline). Call it in `build()`; the listeners are scoped to the widget.
  ///
  /// Realtime and reconnect only *trigger* the existing loaders — pass an
  /// invalidate of the screen's provider(s) as [onChange] — so there is one
  /// data path, never a second hand-merged copy.
  void liveRefresh(List<String> collections, void Function() onChange) {
    for (final collection in collections) {
      listen(collectionEventsProvider(collection), (_, next) {
        if (next.value != null) onChange();
      });
    }
    listen(onlineStatusProvider, (previous, next) {
      if (next.value == OnlineStatus.online &&
          previous?.value == OnlineStatus.offline) {
        onChange();
      }
    });
  }
}
