import 'dart:async';

import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/worklist/worklist.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/foundation.dart';
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
/// The base collections feeding the worklist, for live-sync. The
/// `medication_due` and `case_quarantine` sources are DB *views* (no realtime),
/// so we watch the base collections they derive from. Screens pass this to
/// `WidgetRef.liveRefresh`.
const worklistLiveCollections = [
  'follow_ups',
  'medications',
  'medication_administrations',
  'quarantine_records',
  'cases',
];

/// Re-evaluates the worklist every minute so time-relative items — a dose
/// becoming due, a quarantine ending — surface as their moment arrives, the one
/// thing realtime can't trigger (no data changes, only the clock). The
/// per-minute tick invalidates only the *derived* [worklist], which recomputes
/// against the cached [worklistSource] — no queries, so the constant cadence
/// costs the server nothing (federfall-zosx). Data changes refetch the source
/// via realtime/`liveRefresh`; a much rarer full refetch here reconciles any
/// events missed in between (e.g. while the OS had the app suspended).
/// Invalidate only: AsyncValueView keeps the current list visible during the
/// reload (skipLoadingOnReload), so nothing flashes or shifts unless an item
/// genuinely enters/leaves the due window. Screen-scoped, so the timers stop
/// when neither the Today tab nor the dashboard card is visible.
@riverpod
void worklistTicker(Ref ref) {
  final recompute = Timer.periodic(
    const Duration(minutes: 1),
    (_) => ref.invalidate(worklistProvider),
  );
  final refetch = Timer.periodic(
    const Duration(minutes: 15),
    (_) => ref.invalidate(worklistSourceProvider),
  );
  ref.onDispose(() {
    recompute.cancel();
    refetch.cancel();
  });
}

/// Snapshot of the server data the worklist derives from — everything
/// [buildWorklist] needs except the clock, so due-window membership can be
/// re-checked any number of times without touching the network.
@immutable
class WorklistSource {
  const WorklistSource({
    this.cases = const [],
    this.medicationsDue = const [],
    this.followUps = const [],
    this.lastActivityByCase = const {},
    this.quarantineUntilByCase = const {},
    this.animalNameById = const {},
  });

  /// The signed-in carer's active (not disposed) cases.
  final List<Case> cases;
  final List<MedicationDue> medicationsDue;
  final List<FollowUp> followUps;
  final Map<String, DateTime?> lastActivityByCase;
  final Map<String, DateTime?> quarantineUntilByCase;
  final Map<String, String?> animalNameById;
}

/// Fetches the worklist's inputs. Invalidate THIS provider when data may have
/// changed (realtime event, a dose logged, pull-to-refresh); the clock-only
/// per-minute tick invalidates just the derived [worklist] instead.
@riverpod
Future<WorklistSource> worklistSource(Ref ref) async {
  final me = (await ref.watch(currentUserProvider.future))?.id;
  if (me == null) return const WorklistSource();

  // Repositories all share the resolved client; resolve them together.
  final (
    casesRepo,
    medDueRepo,
    activityRepo,
    animalsRepo,
    followUpsRepo,
    quarantineRepo,
  ) = await (
    ref.watch(casesRepositoryProvider.future),
    ref.watch(medicationDueRepositoryProvider.future),
    ref.watch(caseActivityRepositoryProvider.future),
    ref.watch(animalsRepositoryProvider.future),
    ref.watch(followUpsRepositoryProvider.future),
    ref.watch(caseQuarantineRepositoryProvider.future),
  ).wait;

  final allCases = await casesRepo.list(sort: '-created');
  final myActive = allCases
      .where((c) => c.activeCarer == me && c.status != CaseStatus.disposed)
      .toList();
  if (myActive.isEmpty) return const WorklistSource();

  final animalIds = {for (final c in myActive) c.animal};

  // Independent queries, all fired at once and awaited together.
  final (medicationsDue, followUps, activity, animals, quarantine) = await (
    medDueRepo.mine(me),
    followUpsRepo.openForCarer(me),
    activityRepo.all(),
    animalsRepo.byIds(animalIds),
    quarantineRepo.all(),
  ).wait;

  return WorklistSource(
    cases: myActive,
    medicationsDue: medicationsDue,
    followUps: followUps,
    lastActivityByCase: {for (final a in activity) a.id: a.lastActivity},
    quarantineUntilByCase: {for (final q in quarantine) q.id: q.until},
    animalNameById: {for (final a in animals) a.id: a.name},
  );
}

@riverpod
Future<List<WorklistItem>> worklist(Ref ref) async {
  final source = await ref.watch(worklistSourceProvider.future);
  return buildWorklist(
    cases: source.cases,
    medicationsDue: source.medicationsDue,
    followUps: source.followUps,
    lastActivityByCase: source.lastActivityByCase,
    quarantineUntilByCase: source.quarantineUntilByCase,
    animalNameById: source.animalNameById,
    now: DateTime.now(),
  );
}
