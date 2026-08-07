import 'dart:async';

import 'package:federfall/core/async/parallel_wait.dart';
import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/error/error_message.dart';
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
  'vet_appointments',
  'medications',
  'medication_administrations',
  'quarantine_records',
  'cases',
];

/// How far back unresolved vet appointments are still fetched. A missed
/// appointment stays on the worklist until somebody marks it attended or
/// cancelled, but one forgotten for a month is not a live task any more and
/// must not be queried forever.
const appointmentBacklog = Duration(days: 30);

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
    this.appointments = const [],
    this.lastActivityByCase = const {},
    this.quarantineUntilByCase = const {},
    this.animalNameById = const {},
  });

  /// The signed-in carer's active (not disposed) cases.
  final List<Case> cases;
  final List<MedicationDue> medicationsDue;
  final List<FollowUp> followUps;

  /// Unresolved vet appointments on those cases — including ones beyond the
  /// worklist's own window, which the reminder planner still needs.
  final List<VetAppointment> appointments;
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
    appointmentsRepo,
  ) = await (
    ref.watch(casesRepositoryProvider.future),
    ref.watch(medicationDueRepositoryProvider.future),
    ref.watch(caseActivityRepositoryProvider.future),
    ref.watch(animalsRepositoryProvider.future),
    ref.watch(followUpsRepositoryProvider.future),
    ref.watch(caseQuarantineRepositoryProvider.future),
    ref.watch(vetAppointmentsRepositoryProvider.future),
  ).waitUnwrapped;

  final allCases = await casesRepo.list(sort: '-created');
  final myActive = allCases
      .where((c) => c.activeCarer == me && c.status != CaseStatus.disposed)
      .toList();
  if (myActive.isEmpty) return const WorklistSource();

  final animalIds = {for (final c in myActive) c.animal};

  // Independent queries, all fired at once and awaited together. If ANY of
  // them fails the worklist fails, which is right for these: a worklist
  // missing a source silently would be worse than an error with a retry.
  //
  // Failing loudly does not require failing vaguely, though — hence
  // `waitUnwrapped` rather than `.wait`, which would report a dropped
  // connection as a ParallelWaitError the UI cannot recognise as one
  // (federfall-s5mm).
  final (medicationsDue, followUps, activity, animals, quarantine) = await (
    medDueRepo.mine(me),
    followUpsRepo.openForCarer(me),
    activityRepo.all(),
    animalsRepo.byIds(animalIds),
    quarantineRepo.all(),
  ).waitUnwrapped;

  // Appointments are the exception, and deliberately tolerant. The app/server
  // compatibility gate checks the MAJOR version only, and an APK that
  // auto-updated ahead of its container is the common self-hoster case — such a
  // client 404s on `vet_appointments`. Gathered above that would take
  // down the whole worklist AND every reminder; degrading to "no appointments"
  // costs only the feature that cannot work anyway.
  var appointments = const <VetAppointment>[];
  try {
    appointments = await appointmentsRepo.openForCarer(
      me,
      since: DateTime.now().toUtc().subtract(appointmentBacklog),
    );
  } on Object catch (error, stackTrace) {
    reportCaughtError(
      error,
      stackTrace,
      context: 'Loading vet appointments for the worklist failed',
    );
  }

  return WorklistSource(
    cases: myActive,
    medicationsDue: medicationsDue,
    followUps: followUps,
    appointments: appointments,
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
    appointments: source.appointments,
    lastActivityByCase: source.lastActivityByCase,
    quarantineUntilByCase: source.quarantineUntilByCase,
    animalNameById: source.animalNameById,
    now: DateTime.now(),
  );
}
