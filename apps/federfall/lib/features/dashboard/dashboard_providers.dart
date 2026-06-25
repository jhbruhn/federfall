import 'package:federfall/data/repository_providers.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'dashboard_providers.g.dart';

/// How far ahead a quarantine counts as "ending soon".
const quarantineSoonWindow = Duration(days: 7);

/// Aggregated figures shown on the dashboard (FED-7.1), derived from the set of
/// cases the signed-in user may read — so the scope follows the access rules
/// (carer: own + shared; coordinator/supervisor: org-wide).
@immutable
class DashboardSummary {
  const DashboardSummary({
    required this.activeCount,
    required this.intakesThisYear,
    required this.byStatus,
    required this.quarantineEndingSoon,
    this.inAviaryCount = 0,
  });

  /// Cases that have not yet been disposed.
  final int activeCount;

  /// Cases admitted within the current calendar year.
  final int intakesThisYear;

  /// Animals currently resident in an aviary (lifetime_status = in_aviary).
  final int inAviaryCount;

  /// Active-case counts per status, in [CaseStatus] order (disposed excluded).
  final Map<CaseStatus, int> byStatus;

  /// Active cases whose quarantine ends within [quarantineSoonWindow] (or is
  /// already overdue), soonest first.
  final List<Case> quarantineEndingSoon;
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
  Duration soonWindow = quarantineSoonWindow,
  int inAviaryCount = 0,
}) {
  final byStatus = {for (final s in _activeStatuses) s: 0};
  final soonThreshold = now.add(soonWindow);
  final quarantineSoon = <Case>[];
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
      final q = c.quarantineUntil;
      if (q != null && q.isBefore(soonThreshold)) quarantineSoon.add(c);
    }
    final admitted = c.admittedAt;
    if (admitted != null && admitted.year == now.year) intakes++;
  }

  quarantineSoon.sort(
    (a, b) => a.quarantineUntil!.compareTo(b.quarantineUntil!),
  );

  return DashboardSummary(
    activeCount: active,
    intakesThisYear: intakes,
    byStatus: byStatus,
    quarantineEndingSoon: quarantineSoon,
    inAviaryCount: inAviaryCount,
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
