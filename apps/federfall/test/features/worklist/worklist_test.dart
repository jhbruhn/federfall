import 'package:federfall/features/worklist/worklist.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-06-24 12:00 local — the reference "now" for every case below.
final _now = DateTime(2026, 6, 24, 12);

Case _case(String id, {DateTime? quarantineUntil}) => Case(
  id: id,
  animal: 'a-$id',
  status: CaseStatus.inCare,
  quarantineUntil: quarantineUntil,
);

Medication _med(
  String id, {
  String caseId = 'c1',
  MedicationFrequencyKind? kind,
  int? intervalHours,
  DateTime? startedAt,
  DateTime? endedAt,
  String drug = 'Meloxicam',
}) => Medication(
  id: id,
  caseId: caseId,
  drug: drug,
  frequencyKind: kind,
  intervalHours: intervalHours,
  startedAt: startedAt,
  endedAt: endedAt,
);

MedicationAdministration _dose(String medId, DateTime at) =>
    MedicationAdministration(
      id: 'd-$medId-${at.millisecondsSinceEpoch}',
      caseId: 'c1',
      drug: 'Meloxicam',
      medication: medId,
      administeredAt: at,
    );

void main() {
  group('buildWorklist — medications', () {
    test('scheduled dose is overdue once an interval has passed', () {
      final items = buildWorklist(
        cases: [_case('c1')],
        medications: [
          _med(
            'm1',
            kind: MedicationFrequencyKind.scheduled,
            intervalHours: 12,
          ),
        ],
        administrations: [
          _dose('m1', _now.subtract(const Duration(hours: 13))),
        ],
        now: _now,
      );

      expect(items, hasLength(1));
      expect(items.single.kind, WorklistKind.medicationDue);
      expect(items.single.severity, WorklistSeverity.overdue);
      expect(items.single.drug, 'Meloxicam');
      // Last dose 13h ago + 12h interval = due 1h ago.
      expect(items.single.dueAt, _now.subtract(const Duration(hours: 1)));
    });

    test('a dose given recently is not yet due (outside the window)', () {
      final items = buildWorklist(
        cases: [_case('c1')],
        medications: [
          _med(
            'm1',
            kind: MedicationFrequencyKind.scheduled,
            intervalHours: 48,
          ),
        ],
        administrations: [_dose('m1', _now.subtract(const Duration(hours: 1)))],
        now: _now,
      );
      // Next due in 47h — beyond the 24h window.
      expect(items, isEmpty);
    });

    test('a never-given scheduled med is due at its start time', () {
      final started = _now.subtract(const Duration(hours: 2));
      final items = buildWorklist(
        cases: [_case('c1')],
        medications: [
          _med(
            'm1',
            kind: MedicationFrequencyKind.scheduled,
            intervalHours: 12,
            startedAt: started,
          ),
        ],
        administrations: const [],
        now: _now,
      );
      expect(items.single.dueAt, started);
      expect(items.single.severity, WorklistSeverity.overdue);
    });

    test('a once med drops off after it has been given', () {
      final items = buildWorklist(
        cases: [_case('c1')],
        medications: [
          _med(
            'm1',
            kind: MedicationFrequencyKind.once,
            startedAt: _now.subtract(const Duration(hours: 3)),
          ),
        ],
        administrations: [_dose('m1', _now.subtract(const Duration(hours: 2)))],
        now: _now,
      );
      expect(items, isEmpty);
    });

    test('as-needed meds never appear', () {
      final items = buildWorklist(
        cases: [_case('c1')],
        medications: [_med('m1', kind: MedicationFrequencyKind.asNeeded)],
        administrations: const [],
        now: _now,
      );
      expect(items, isEmpty);
    });

    test('an ended prescription is excluded', () {
      final items = buildWorklist(
        cases: [_case('c1')],
        medications: [
          _med(
            'm1',
            kind: MedicationFrequencyKind.scheduled,
            intervalHours: 12,
            startedAt: _now.subtract(const Duration(days: 2)),
            endedAt: _now.subtract(const Duration(hours: 1)),
          ),
        ],
        administrations: const [],
        now: _now,
      );
      expect(items, isEmpty);
    });

    test('meds on cases outside the scoped set are ignored', () {
      final items = buildWorklist(
        cases: [_case('c1')],
        medications: [
          _med(
            'm1',
            caseId: 'other',
            kind: MedicationFrequencyKind.scheduled,
            intervalHours: 12,
            startedAt: _now.subtract(const Duration(hours: 1)),
          ),
        ],
        administrations: const [],
        now: _now,
      );
      expect(items, isEmpty);
    });
  });

  group('buildWorklist — quarantine', () {
    test('quarantine ending within the window is upcoming', () {
      final until = _now.add(const Duration(days: 2));
      final items = buildWorklist(
        cases: [_case('c1', quarantineUntil: until)],
        medications: const [],
        administrations: const [],
        now: _now,
      );
      expect(items.single.kind, WorklistKind.quarantineEnding);
      expect(items.single.severity, WorklistSeverity.upcoming);
      expect(items.single.dueAt, until);
    });

    test('quarantine in the past is overdue', () {
      final items = buildWorklist(
        cases: [
          _case('c1', quarantineUntil: _now.subtract(const Duration(days: 1))),
        ],
        medications: const [],
        administrations: const [],
        now: _now,
      );
      expect(items.single.severity, WorklistSeverity.overdue);
    });

    test('quarantine far in the future does not appear', () {
      final items = buildWorklist(
        cases: [
          _case('c1', quarantineUntil: _now.add(const Duration(days: 30))),
        ],
        medications: const [],
        administrations: const [],
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
        medications: const [],
        administrations: const [],
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
        medications: const [],
        administrations: const [],
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
        medications: const [],
        administrations: const [],
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
        medications: const [],
        administrations: const [],
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
        medications: const [],
        administrations: const [],
        lastActivityByCase: {'c1': _now.subtract(const Duration(days: 2))},
        now: _now,
      );
      expect(items, isEmpty);
    });

    test('a case absent from the activity map is never stale', () {
      final items = buildWorklist(
        cases: [_case('c1')],
        medications: const [],
        administrations: const [],
        now: _now,
      );
      expect(items, isEmpty);
    });
  });

  test('items are sorted soonest-due first', () {
    final items = buildWorklist(
      cases: [_case('c1', quarantineUntil: _now.add(const Duration(days: 1)))],
      medications: [
        _med(
          'm1',
          kind: MedicationFrequencyKind.scheduled,
          intervalHours: 6,
          startedAt: _now.subtract(const Duration(hours: 5)),
        ),
      ],
      administrations: const [],
      now: _now,
    );

    expect(items, hasLength(2));
    // Med due 5h ago sorts before the quarantine ending tomorrow.
    expect(items.first.kind, WorklistKind.medicationDue);
    expect(items.last.kind, WorklistKind.quarantineEnding);
  });
}
