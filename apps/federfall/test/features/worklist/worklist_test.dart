import 'package:federfall/features/worklist/worklist.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-06-24 12:00 local — the reference "now" for every case below.
final _now = DateTime(2026, 6, 24, 12);

Case _case(String id) => Case(
  id: id,
  animal: 'a-$id',
  status: CaseStatus.inCare,
);

/// A `medication_due` row with its next-due already computed (server-side in
/// production; the next-due math itself is covered by the backend rule tests).
MedicationDue _due(
  String id, {
  String caseId = 'c1',
  DateTime? nextDue,
  String drug = 'Meloxicam',
}) => MedicationDue(id: id, caseId: caseId, drug: drug, nextDue: nextDue);

void main() {
  group('buildWorklist — medications', () {
    test('a med due within the window appears, overdue and with its plan', () {
      final items = buildWorklist(
        cases: [_case('c1')],
        medicationsDue: [
          _due('m1', nextDue: _now.subtract(const Duration(hours: 1))),
        ],
        now: _now,
      );

      expect(items, hasLength(1));
      expect(items.single.kind, WorklistKind.medicationDue);
      expect(items.single.severity, WorklistSeverity.overdue);
      expect(items.single.drug, 'Meloxicam');
      // The plan is reconstructed so a dose can be logged from the worklist.
      expect(items.single.medication?.id, 'm1');
    });

    test('a med due beyond the window is excluded', () {
      final items = buildWorklist(
        cases: [_case('c1')],
        medicationsDue: [
          _due('m1', nextDue: _now.add(const Duration(hours: 47))),
        ],
        now: _now,
      );
      expect(items, isEmpty);
    });

    test('a row with no next-due is skipped', () {
      final items = buildWorklist(
        cases: [_case('c1')],
        medicationsDue: [_due('m1')],
        now: _now,
      );
      expect(items, isEmpty);
    });

    test('meds on cases outside the scoped set are ignored', () {
      final items = buildWorklist(
        cases: [_case('c1')],
        medicationsDue: [
          _due(
            'm1',
            caseId: 'other',
            nextDue: _now.subtract(const Duration(hours: 1)),
          ),
        ],
        now: _now,
      );
      expect(items, isEmpty);
    });
  });

  group('buildWorklist — quarantine', () {
    test('quarantine ending within the window is upcoming', () {
      final until = _now.add(const Duration(days: 2));
      final items = buildWorklist(
        cases: [_case('c1')],
        medicationsDue: const [],
        quarantineUntilByCase: {'c1': until},
        now: _now,
      );
      expect(items.single.kind, WorklistKind.quarantineEnding);
      expect(items.single.severity, WorklistSeverity.upcoming);
      expect(items.single.dueAt, until);
    });

    test('quarantine in the past is overdue', () {
      final items = buildWorklist(
        cases: [_case('c1')],
        medicationsDue: const [],
        quarantineUntilByCase: {
          'c1': _now.subtract(const Duration(days: 1)),
        },
        now: _now,
      );
      expect(items.single.severity, WorklistSeverity.overdue);
    });

    test('quarantine far in the future does not appear', () {
      final items = buildWorklist(
        cases: [_case('c1')],
        medicationsDue: const [],
        quarantineUntilByCase: {'c1': _now.add(const Duration(days: 30))},
        now: _now,
      );
      expect(items, isEmpty);
    });
  });

  group('buildWorklist — follow-ups', () {
    FollowUp followUp({
      required DateTime dueAt,
      String id = 'f1',
      DateTime? doneAt,
      String note = 'Recheck wound',
    }) => FollowUp(
      id: id,
      caseId: 'c1',
      dueAt: dueAt,
      doneAt: doneAt,
      note: note,
    );

    test('an open recheck due within the window appears', () {
      final due = _now.add(const Duration(days: 2));
      final items = buildWorklist(
        cases: [_case('c1')],
        medicationsDue: const [],
        followUps: [followUp(dueAt: due)],
        now: _now,
      );
      expect(items.single.kind, WorklistKind.followUpDue);
      expect(items.single.severity, WorklistSeverity.upcoming);
      expect(items.single.dueAt, due);
      expect(items.single.followUp?.note, 'Recheck wound');
    });

    test('a completed recheck is excluded', () {
      final items = buildWorklist(
        cases: [_case('c1')],
        medicationsDue: const [],
        followUps: [
          followUp(
            dueAt: _now.subtract(const Duration(days: 1)),
            doneAt: _now,
          ),
        ],
        now: _now,
      );
      expect(items, isEmpty);
    });

    test('a recheck far in the future does not appear', () {
      final items = buildWorklist(
        cases: [_case('c1')],
        medicationsDue: const [],
        followUps: [followUp(dueAt: _now.add(const Duration(days: 30)))],
        now: _now,
      );
      expect(items, isEmpty);
    });
  });

  group('buildWorklist — stale cases', () {
    test('a case untouched past the threshold is flagged stale', () {
      final last = _now.subtract(const Duration(days: 10));
      final items = buildWorklist(
        cases: [_case('c1')],
        medicationsDue: const [],
        lastActivityByCase: {'c1': last},
        now: _now,
      );
      expect(items.single.kind, WorklistKind.staleCase);
      expect(items.single.severity, WorklistSeverity.overdue);
      expect(items.single.dueAt, last);
    });

    test('a recently-touched case is not stale', () {
      final items = buildWorklist(
        cases: [_case('c1')],
        medicationsDue: const [],
        lastActivityByCase: {'c1': _now.subtract(const Duration(days: 2))},
        now: _now,
      );
      expect(items, isEmpty);
    });

    test('a case absent from the activity map is never stale', () {
      final items = buildWorklist(
        cases: [_case('c1')],
        medicationsDue: const [],
        now: _now,
      );
      expect(items, isEmpty);
    });
  });

  test('items are sorted soonest-due first', () {
    final items = buildWorklist(
      cases: [_case('c1')],
      medicationsDue: [
        _due('m1', nextDue: _now.subtract(const Duration(hours: 5))),
      ],
      quarantineUntilByCase: {'c1': _now.add(const Duration(days: 1))},
      now: _now,
    );

    expect(items, hasLength(2));
    // Med due 5h ago sorts before the quarantine ending tomorrow.
    expect(items.first.kind, WorklistKind.medicationDue);
    expect(items.last.kind, WorklistKind.quarantineEnding);
  });
}
