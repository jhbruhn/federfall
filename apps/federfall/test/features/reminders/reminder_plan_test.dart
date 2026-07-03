import 'package:federfall/features/reminders/reminder_plan.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart' hide Finder;

/// 2026-06-24 12:00 UTC — the reference "now" for every case below.
final _now = DateTime.utc(2026, 6, 24, 12);

final AppLocalizations _l10n = lookupAppLocalizations(const Locale('en'));

Case _case(String id, {String? number}) => Case(
  id: id,
  animal: 'a-$id',
  caseNumber: number,
  status: CaseStatus.inCare,
);

MedicationDue _due(
  String id, {
  String caseId = 'c1',
  DateTime? nextDue,
  String drug = 'Meloxicam',
  double? dose,
  String? doseUnit,
}) => MedicationDue(
  id: id,
  caseId: caseId,
  drug: drug,
  dose: dose,
  doseUnit: doseUnit,
  nextDue: nextDue,
);

List<PlannedReminder> _plan(
  List<MedicationDue> due, {
  List<Case>? cases,
  Map<String, String?> animalNames = const {'a-c1': 'Bella'},
}) => planMedicationReminders(
  l10n: _l10n,
  medicationsDue: due,
  casesById: {
    for (final c in cases ?? [_case('c1', number: '2026-001')]) c.id: c,
  },
  animalNameById: animalNames,
  now: _now,
);

void main() {
  test('a future due becomes one reminder with title, body and payload', () {
    final planned = _plan([
      _due(
        'm1',
        nextDue: _now.add(const Duration(hours: 6)),
        dose: 0.3,
        doseUnit: 'ml',
      ),
    ]);

    expect(planned, hasLength(1));
    final r = planned.single;
    expect(r.id, reminderNotificationId('m1'));
    expect(r.title, 'Medication due: Meloxicam');
    expect(r.body, '0.3 ml — 2026-001 · Bella');
    expect(r.dueAtUtc, _now.add(const Duration(hours: 6)));
    expect(r.payload, '/cases/c1');
  });

  test('already-due and overdue rows are skipped — the worklist owns those, '
      'a notification would re-fire on every reconcile', () {
    final planned = _plan([
      _due('m1', nextDue: _now),
      _due('m2', nextDue: _now.subtract(const Duration(hours: 2))),
      _due('m3'),
    ]);
    expect(planned, isEmpty);
  });

  test('a due whose case is not in scope is skipped', () {
    final planned = _plan([
      _due('m1', caseId: 'other', nextDue: _now.add(const Duration(hours: 1))),
    ]);
    expect(planned, isEmpty);
  });

  test('body falls back to the unnumbered-case placeholder and drops a '
      'missing dose', () {
    final planned = _plan(
      [_due('m1', nextDue: _now.add(const Duration(hours: 1)))],
      cases: [_case('c1')],
      animalNames: const {},
    );
    expect(planned.single.body, 'Unnumbered case');
  });

  test('notification ids are stable per prescription and fit a 32-bit int', () {
    expect(
      reminderNotificationId('abc123def456xyz'),
      reminderNotificationId('abc123def456xyz'),
    );
    expect(
      reminderNotificationId('m1'),
      isNot(reminderNotificationId('m2')),
    );
    final id = reminderNotificationId('abc123def456xyz');
    expect(id, inInclusiveRange(0, 0x7fffffff));
  });
}
