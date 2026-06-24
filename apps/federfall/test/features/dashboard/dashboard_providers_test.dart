import 'package:federfall/features/dashboard/dashboard_providers.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter_test/flutter_test.dart';

Case _case({
  required String id,
  CaseStatus? status,
  DateTime? admittedAt,
  DateTime? quarantineUntil,
}) => Case(
  id: id,
  animal: 'a-$id',
  status: status,
  admittedAt: admittedAt,
  quarantineUntil: quarantineUntil,
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
      _case(
        id: 'far',
        status: CaseStatus.inCare,
        quarantineUntil: now.add(const Duration(days: 30)),
      ),
      _case(
        id: 'soon',
        status: CaseStatus.inCare,
        quarantineUntil: now.add(const Duration(days: 3)),
      ),
      _case(
        id: 'overdue',
        status: CaseStatus.inCare,
        quarantineUntil: now.subtract(const Duration(days: 2)),
      ),
      // Disposed cases never surface even if their quarantine is near.
      _case(
        id: 'disposed',
        status: CaseStatus.disposed,
        quarantineUntil: now.add(const Duration(days: 1)),
      ),
    ], now);

    expect(
      s.quarantineEndingSoon.map((c) => c.id).toList(),
      ['overdue', 'soon'],
    );
  });
}
