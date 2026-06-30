import 'package:federfall/features/dashboard/dashboard_providers.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter_test/flutter_test.dart';

Case _case({
  required String id,
  CaseStatus? status,
  DateTime? admittedAt,
}) => Case(
  id: id,
  animal: 'a-$id',
  status: status,
  admittedAt: admittedAt,
);

void main() {
  final now = DateTime(2026, 6, 23);

  test('counts active cases and excludes disposed', () {
    final s = buildDashboardSummary([
      _case(id: '1', status: CaseStatus.inCare),
      _case(id: '2', status: CaseStatus.readyForRelease),
      _case(id: '3', status: CaseStatus.disposed),
    ], now);

    expect(s.activeCount, 2);
  });

  test('counts intakes in the current calendar year only', () {
    final s = buildDashboardSummary([
      _case(id: '1', admittedAt: DateTime(2026, 3, 15)),
      _case(id: '2', admittedAt: DateTime(2026, 12, 31)),
      _case(id: '3', admittedAt: DateTime(2025, 12, 31)),
      _case(id: '4'),
    ], now);

    expect(s.intakesThisYear, 2);
  });

  test('breaks active cases down by status in enum order', () {
    final s = buildDashboardSummary([
      _case(id: '1', status: CaseStatus.inCare),
      _case(id: '2', status: CaseStatus.inCare),
      _case(id: '3', status: CaseStatus.readyForRelease),
      _case(id: '4', status: CaseStatus.disposed),
    ], now);

    expect(s.byStatus[CaseStatus.inCare], 2);
    expect(s.byStatus[CaseStatus.readyForRelease], 1);
    expect(s.byStatus.containsKey(CaseStatus.disposed), isFalse);
    expect(s.byStatus.keys.toList(), const [
      CaseStatus.inCare,
      CaseStatus.readyForRelease,
    ]);
  });

  test('quarantine ending soon: within window or overdue, soonest first', () {
    final s = buildDashboardSummary([
      _case(id: 'far', status: CaseStatus.inCare),
      _case(id: 'soon', status: CaseStatus.inCare),
      _case(id: 'overdue', status: CaseStatus.inCare),
      // Disposed cases never surface even if their quarantine is near.
      _case(id: 'disposed', status: CaseStatus.disposed),
    ], now, quarantineUntilByCase: {
      'far': now.add(const Duration(days: 30)),
      'soon': now.add(const Duration(days: 3)),
      'overdue': now.subtract(const Duration(days: 2)),
      'disposed': now.add(const Duration(days: 1)),
    });

    expect(
      s.quarantineEndingSoon.map((c) => c.id).toList(),
      ['overdue', 'soon'],
    );
  });
}
