import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/connectivity/connectivity.dart';
import 'package:federfall/core/realtime/collection_events.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/worklist/worklist.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'worklist_providers.g.dart';

/// The signed-in carer's derived worklist (UX Phase D, cr3.1): medications due
/// and quarantines ending on the cases they are responsible for.
///
/// Scope is the carer's own active cases (`active_carer == me`, not disposed).
/// Each source is one query — medications-due via the `medication_due` view
/// (next-due computed server-side), open rechecks and animals via single
/// filtered lists, last-activity via the `case_activity` view — all issued
/// concurrently and folded into the pure [buildWorklist]. Returns an empty list
/// when signed out.
/// The base collections feeding the worklist. The `medication_due` source is a
/// DB *view* (no realtime), so we watch the base collections it derives from.
const _worklistCollections = [
  'follow_ups',
  'medications',
  'medication_administrations',
  'cases',
];

/// Live-sync for the worklist (Pattern A): re-fetches the worklist when any of
/// its source collections change, and on reconnect. The today screen watches
/// this to activate it. Over-invalidating on org-wide events is fine — the
/// refetch is a handful of cache-backed, carer-scoped queries.
@riverpod
void worklistLive(Ref ref) {
  for (final collection in _worklistCollections) {
    ref.listen(collectionEventsProvider(collection), (_, next) {
      if (next.value != null) ref.invalidate(worklistProvider);
    });
  }
  ref.listen(onlineStatusProvider, (prev, next) {
    if (next.value == OnlineStatus.online &&
        prev?.value == OnlineStatus.offline) {
      ref.invalidate(worklistProvider);
    }
  });
}

@riverpod
Future<List<WorklistItem>> worklist(Ref ref) async {
  final me = (await ref.watch(currentUserProvider.future))?.id;
  if (me == null) return const [];

  // Repositories all share the resolved client; resolve them together.
  final (
    casesRepo,
    medDueRepo,
    activityRepo,
    animalsRepo,
    followUpsRepo,
  ) = await (
    ref.watch(casesRepositoryProvider.future),
    ref.watch(medicationDueRepositoryProvider.future),
    ref.watch(caseActivityRepositoryProvider.future),
    ref.watch(animalsRepositoryProvider.future),
    ref.watch(followUpsRepositoryProvider.future),
  ).wait;

  final allCases = await casesRepo.list(sort: '-created');
  final myActive = allCases
      .where((c) => c.activeCarer == me && c.status != CaseStatus.disposed)
      .toList();
  if (myActive.isEmpty) return const [];

  final animalIds = {for (final c in myActive) c.animal};

  // Five fixed queries, all independent — fire them at once and await together.
  final (medicationsDue, followUps, activity, animals) = await (
    medDueRepo.mine(me),
    followUpsRepo.openForCarer(me),
    activityRepo.all(),
    animalsRepo.byIds(animalIds),
  ).wait;

  return buildWorklist(
    cases: myActive,
    medicationsDue: medicationsDue,
    followUps: followUps,
    lastActivityByCase: {for (final a in activity) a.id: a.lastActivity},
    animalNameById: {for (final a in animals) a.id: a.name},
    now: DateTime.now(),
  );
}
