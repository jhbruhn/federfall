import 'package:federfall/core/connectivity/connectivity.dart';
import 'package:federfall/core/realtime/collection_events.dart';
import 'package:federfall/features/cases/case_timeline.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'case_realtime.g.dart';

/// The collections behind the case timeline — the realtime sources we watch.
/// 'case_shares' is included because a share granted/revoked on THIS case
/// changes the viewer's own access without touching the case record; the
/// default event filter (`data['case'] == caseId`) catches it, so a recipient
/// gains (or loses) the detail view live instead of needing a full reload.
const _caseTimelineCollections = [
  'cases',
  'case_shares',
  'journal_entries',
  'weights',
  'case_conditions',
  'medications',
  'medication_administrations',
  'placements',
  'dispositions',
  'follow_ups',
  'exams',
  'exam_findings',
  'markings',
  'quarantine_records',
];

/// Live-sync for a case detail view (Pattern A): subscribes to the collections
/// behind the timeline and re-fetches — via the same [invalidateCaseTimeline]
/// the pull-to-refresh uses — when an event for THIS case arrives, so a
/// teammate's change on a shared case shows up without a manual refresh.
///
/// Realtime is only a *trigger* into the existing loaders; there is no second,
/// hand-merged copy of the data. The detail screen watches this to activate it,
/// and calls [refresh] for pull-to-refresh — both go through this notifier's
/// single [Ref], so the source list lives in exactly one place.
@riverpod
class CaseLive extends _$CaseLive {
  late String _caseId;
  late String _animalId;

  @override
  void build(String caseId, String animalId) {
    _caseId = caseId;
    _animalId = animalId;

    for (final collection in _caseTimelineCollections) {
      ref.listen(collectionEventsProvider(collection), (_, next) {
        final event = next.value;
        if (event == null) return;
        final data = event.record?.data ?? const <String, dynamic>{};
        final belongs = switch (collection) {
          'cases' => event.record?.id == caseId,
          'markings' => data['animal'] == animalId,
          // exam_findings has no `case` field (it points at an exam); refetch
          // on any of its events rather than resolve the parent.
          'exam_findings' => true,
          _ => data['case'] == caseId,
        };
        if (belongs) _refetch();
      });
    }

    // Catch up on anything missed while offline.
    ref.listen(onlineStatusProvider, (prev, next) {
      if (next.value == OnlineStatus.online &&
          prev?.value == OnlineStatus.offline) {
        _refetch();
      }
    });
  }

  void _refetch() {
    invalidateCaseTimeline(ref, caseId: _caseId, animalId: _animalId);
    ref.invalidate(caseByIdProvider(_caseId));
  }

  /// Manual pull-to-refresh: rebuild the timeline and header, awaiting the case
  /// re-fetch so the refresh spinner lasts until the data is back.
  Future<void> refresh() async {
    invalidateCaseTimeline(ref, caseId: _caseId, animalId: _animalId);
    ref
      ..invalidate(animalByIdProvider(_animalId))
      ..invalidate(caseByIdProvider(_caseId));
    await ref.read(caseByIdProvider(_caseId).future);
  }
}
