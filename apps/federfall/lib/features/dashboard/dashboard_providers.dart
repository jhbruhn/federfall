import 'package:federfall/core/async/parallel_wait.dart';
import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/placements/placements_providers.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'dashboard_providers.g.dart';

/// Aggregated figures shown on the dashboard (FED-7.1), counted server-side
/// over the cases the signed-in user may read — so the scope follows the access
/// rules (carer: own + shared; coordinator/supervisor: org-wide).
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
  /// workload card (federfall-9mit). Read from the `case_carer_load` view,
  /// which counts open cases exactly as the server's guard on deleting a
  /// member does (`active_carer = {:id} && status != 'disposed'`,
  /// `main.pb.js`), so the two never disagree.
  ///
  /// **Empty for a carer, legitimately.** That view is org-wide by
  /// construction and its list rule admits coordinators and supervisors only;
  /// a list request applies the rule as a filter, so a carer receives no rows
  /// rather than an error. Nothing is lost: their own case list holds other
  /// people's cases only where they were shared, so per-carer figures would be
  /// a fragment anyway — which is why the only consumer
  /// ([carerWorkloadProvider], via the workload card) already gates on
  /// `canViewReports`.
  final Map<String, int> openByCarer;
}

/// The active (non-disposed) statuses, in display order.
const List<CaseStatus> _activeStatuses = [
  CaseStatus.inCare,
  CaseStatus.readyForRelease,
];

/// Pure assembly of the server-side counts into a [DashboardSummary]. Kept
/// separate from the provider so it can be unit-tested without PocketBase.
///
/// [DashboardSummary.activeCount] comes from [totalCases] MINUS
/// [disposedCases] rather than from a `status != 'disposed'` count. The
/// original reason was a suspect `!=` (federfall-jt5u, since probed and
/// cleared); what keeps the subtraction is that it counts a case with no
/// status at all as active, which is what "has not yet been disposed" means,
/// and that both counts are already on hand.
DashboardSummary buildDashboardSummary({
  required int totalCases,
  required int disposedCases,
  required Map<CaseStatus, int> activeByStatus,
  required int intakesThisYear,
  int inAviaryCount = 0,
  List<CarerCaseLoad> carerLoad = const [],
}) {
  final active = totalCases - disposedCases;
  return DashboardSummary(
    // The two counts are separate requests, so a case disposed between them
    // can make the difference negative. A KPI tile reading "-1" would look
    // broken; a momentarily low 0 just resolves on the next refresh.
    activeCount: active < 0 ? 0 : active,
    intakesThisYear: intakesThisYear,
    byStatus: {for (final s in _activeStatuses) s: activeByStatus[s] ?? 0},
    inAviaryCount: inAviaryCount,
    openByCarer: {
      for (final row in carerLoad)
        // `active_carer` is optional server-side, and the view only emits rows
        // for cases that have one — but a defensive skip keeps an empty id from
        // rendering as a nameless workload row if that ever changes.
        if (row.carer.isNotEmpty) row.carer: row.openCases,
    },
  );
}

/// Dashboard figures for the signed-in user, every one of them counted
/// **server-side** (federfall-s0wk).
///
/// This used to fetch the whole `cases` and `animals` collections and tally
/// them on the device — the load pattern federfall-80tc removed from the CSV
/// export and federfall-nmwi from the statistics screen. Each figure is now a
/// request that transfers one row, and the scope still follows the access
/// rules because the list rule is applied to a count exactly as it is to a
/// list: org-wide for a coordinator or supervisor, own + shared for a carer.
/// That matters for more than cost — it is what keeps every KPI tile equal to
/// the case list it taps through to.
///
/// The year boundary is deliberately built here rather than server-side: it
/// belongs to the caller. A view or a SQL expression would resolve it in UTC
/// and put a bird admitted at 00:30 on New Year's Day in UTC+1 in the wrong
/// year — the same disagreement with the statistics screen this issue's first
/// half fixed. Local midnights, converted to UTC on the way out.
@riverpod
Future<DashboardSummary> dashboardSummary(Ref ref) async {
  final (casesRepo, animalsRepo, carerLoadRepo) = await (
    ref.watch(casesRepositoryProvider.future),
    ref.watch(animalsRepositoryProvider.future),
    ref.watch(carerLoadRepositoryProvider.future),
  ).waitUnwrapped;

  final now = DateTime.now();
  final yearStart = DateTime(now.year);
  final nextYearStart = DateTime(now.year + 1);

  // The workload view is read alongside the counts, but its failure is not
  // fatal — see [_carerLoadOrNone].
  final carerLoad = _carerLoadOrNone(carerLoadRepo);
  final counts = await _counted([
    casesRepo.count(),
    casesRepo.countWithStatus(CaseStatus.disposed),
    casesRepo.countAdmittedBetween(yearStart, nextYearStart),
    animalsRepo.countHoused(),
    // Driven off [_activeStatuses] rather than named one by one, so the tiles
    // and this fetch cannot drift apart when a status is added.
    for (final s in _activeStatuses) casesRepo.countWithStatus(s),
  ]);
  final [total, disposed, intakes, inAviary, ...byStatus] = counts;

  return buildDashboardSummary(
    totalCases: total,
    disposedCases: disposed,
    activeByStatus: {
      for (var i = 0; i < _activeStatuses.length; i++)
        _activeStatuses[i]: byStatus[i],
    },
    intakesThisYear: intakes,
    inAviaryCount: inAviary,
    carerLoad: await carerLoad,
  );
}

/// Awaits [counts] concurrently, propagating the FIRST underlying error — the
/// homogeneous counterpart to `waitUnwrapped`, and the same reasoning: a
/// wrapped failure is one the app's error mapping cannot read. See
/// `core/async/parallel_wait.dart`.
Future<List<int>> _counted(List<Future<int>> counts) => Future.wait(counts);

/// The org-wide carer load, or nothing when it cannot be read.
///
/// Two ways that happens, and neither should cost the user their dashboard.
/// A carer's list rule matches no rows, which is simply an empty list. And an
/// app talking to an older server **within the same major** — permitted, since
/// only the major is the wire contract — finds no `case_carer_load` collection
/// at all and gets a 404. The card this feeds is supplementary and already
/// `canViewReports`-gated, while the counts beside it are awaited unguarded, so
/// a genuine outage still surfaces there rather than being swallowed here.
Future<List<CarerCaseLoad>> _carerLoadOrNone(
  PbCarerLoadRepository repo,
) async {
  try {
    return await repo.all();
  } on RepositoryException catch (error, stackTrace) {
    reportCaughtError(
      error,
      stackTrace,
      context: 'Dashboard carer workload unavailable; showing no counts',
    );
    return const [];
  }
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
/// counts come from [DashboardSummary.openByCarer], i.e. the org-wide
/// `case_carer_load` view — which those two roles read and a carer does not,
/// so for a carer this resolves to a roster with no counts and the card is
/// hidden anyway.
@riverpod
Future<List<CarerWorkload>> carerWorkload(Ref ref) async {
  final (summary, usersRepo) = await (
    ref.watch(dashboardSummaryProvider.future),
    ref.watch(usersRepositoryProvider.future),
  ).waitUnwrapped;
  return buildCarerWorkload(await usersRepo.members(), summary.openByCarer);
}
