import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/placements/placements_providers.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'dashboard_providers.g.dart';

/// Aggregated figures shown on the dashboard (FED-7.1), derived from the set of
/// cases the signed-in user may read — so the scope follows the access rules
/// (carer: own + shared; coordinator/supervisor: org-wide).
@immutable
class DashboardSummary {
  const DashboardSummary({
    required this.activeCount,
    required this.intakesThisYear,
    required this.byStatus,
    this.inAviaryCount = 0,
    this.openByCarer = const {},
  });

  /// Cases that have not yet been disposed.
  final int activeCount;

  /// Cases admitted within the current calendar year.
  final int intakesThisYear;

  /// Animals currently resident in an aviary (lifetime_status = in_aviary).
  final int inAviaryCount;

  /// Active-case counts per status, in [CaseStatus] order (disposed excluded).
  final Map<CaseStatus, int> byStatus;

  /// Open (non-disposed) case count per active-carer user id, for the carer
  /// workload card (federfall-9mit). Same definition of "open caseload" the
  /// server uses to guard deleting a member (`active_carer = {:id} && status
  /// != 'disposed'`, `main.pb.js`), so the two never disagree.
  ///
  /// Only meaningful for coordinators/supervisors, who read org-wide: a
  /// carer's own case list holds other people's cases only where they were
  /// shared, so their per-carer figures would be a fragment. The card that
  /// shows this gates on `canViewReports` for that reason.
  final Map<String, int> openByCarer;
}

/// The active (non-disposed) statuses, in display order.
const List<CaseStatus> _activeStatuses = [
  CaseStatus.inCare,
  CaseStatus.readyForRelease,
];

/// Pure aggregation of [cases] into a [DashboardSummary] as of [now]. Kept
/// separate from the provider so it can be unit-tested without PocketBase.
DashboardSummary buildDashboardSummary(
  List<Case> cases,
  DateTime now, {
  int inAviaryCount = 0,
}) {
  final byStatus = {for (final s in _activeStatuses) s: 0};
  final openByCarer = <String, int>{};
  var active = 0;
  var intakes = 0;

  for (final c in cases) {
    final isActive = c.status != CaseStatus.disposed;
    if (isActive) {
      active++;
      final status = c.status;
      if (status != null && byStatus.containsKey(status)) {
        byStatus[status] = byStatus[status]! + 1;
      }
      // `active_carer` is optional server-side, so an unassigned open case is
      // possible (rare — the create rule pins it to the caller). It belongs to
      // nobody's workload, so it is left out rather than bucketed under ''.
      final carer = c.activeCarer;
      if (carer != null && carer.isNotEmpty) {
        openByCarer[carer] = (openByCarer[carer] ?? 0) + 1;
      }
    }
    // `.toLocal()` is load-bearing (federfall-s0wk): `admittedAt` is UTC —
    // `pbDate` normalises every timestamp with `.toUtc()` — while [now] is the
    // device's local time, so comparing the two years directly put a bird
    // admitted at 00:30 on New Year's Day in UTC+1 into LAST year here and
    // into this one on the statistics screen, which resolves the boundary
    // through the caller's own offset server-side. Same case, same org, two
    // answers.
    final admitted = c.admittedAt?.toLocal();
    if (admitted != null && admitted.year == now.year) intakes++;
  }

  return DashboardSummary(
    activeCount: active,
    intakesThisYear: intakes,
    byStatus: byStatus,
    inAviaryCount: inAviaryCount,
    openByCarer: openByCarer,
  );
}

/// Dashboard figures for the signed-in user. Reads every case the access rules
/// expose, then aggregates client-side.
@riverpod
Future<DashboardSummary> dashboardSummary(Ref ref) async {
  final (casesRepo, animalsRepo) = await (
    ref.watch(casesRepositoryProvider.future),
    ref.watch(animalsRepositoryProvider.future),
  ).wait;
  final (cases, animals) = await (
    casesRepo.list(sort: '-created'),
    animalsRepo.list(),
  ).wait;
  final inAviary = animals
      .where((a) => a.lifetimeStatus == LifetimeStatus.inAviary)
      .length;
  return buildDashboardSummary(
    cases,
    DateTime.now(),
    inAviaryCount: inAviary,
  );
}

/// One row of the carer workload card: a team member and their open caseload.
@immutable
class CarerWorkload {
  const CarerWorkload({required this.user, required this.openCases});

  final AppUser user;

  /// Open (non-disposed) cases where [user] is the active carer.
  final int openCases;
}

/// Pure join of the team roster with [openByCarer], busiest carer first then
/// name — so the card leads with who needs relieving and ends with who has
/// capacity. Kept separate from the provider so it can be unit-tested.
///
/// A member is listed when they can currently take cases (active, non-guest)
/// **or** when they still hold open ones. That second clause is not
/// hypothetical: deactivating a member is not blocked on their caseload (only
/// deleting them is, `main.pb.js`), so a deactivated carer can sit on open
/// cases nobody can be handed — exactly the row a coordinator has to see.
List<CarerWorkload> buildCarerWorkload(
  List<AppUser> members,
  Map<String, int> openByCarer,
) {
  return [
    for (final m in members)
      if ((m.isActive && m.role != UserRole.guest) ||
          (openByCarer[m.id] ?? 0) > 0)
        CarerWorkload(user: m, openCases: openByCarer[m.id] ?? 0),
  ]..sort((a, b) {
    final byLoad = b.openCases.compareTo(a.openCases);
    if (byLoad != 0) return byLoad;
    return memberLabel(a.user).toLowerCase().compareTo(
      memberLabel(b.user).toLowerCase(),
    );
  });
}

/// Open caseload per team member, for the dashboard's carer workload card
/// (federfall-9mit).
///
/// Reads the *full* roster (`members()`, active and not) rather than the
/// handoff picker's active-only list, so a deactivated member's stranded cases
/// still surface — see [buildCarerWorkload].
///
/// Coordinators/supervisors only; the card gates on `canViewReports`. The
/// counts ride on [dashboardSummaryProvider]'s case list, which is scoped to
/// what the caller may read — org-wide for those two roles, a fragment for a
/// carer (see [DashboardSummary.openByCarer]).
@riverpod
Future<List<CarerWorkload>> carerWorkload(Ref ref) async {
  final summaryFuture = ref.watch(dashboardSummaryProvider.future);
  final usersRepo = await ref.watch(usersRepositoryProvider.future);
  final (summary, members) = await (summaryFuture, usersRepo.members()).wait;
  return buildCarerWorkload(members, summary.openByCarer);
}
