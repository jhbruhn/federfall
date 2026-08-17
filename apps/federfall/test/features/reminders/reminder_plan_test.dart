import 'package:federfall/features/reminders/reminder_plan.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart' hide Finder;
import 'package:intl/date_symbol_data_local.dart';

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

VetAppointment _appointment(
  String id, {
  String caseId = 'c1',
  DateTime? startsAt,
  String? vet = 'Dr. Vogel',
  int? leadMinutes,
  bool muted = false,
  DateTime? attendedAt,
  DateTime? cancelledAt,
}) => VetAppointment(
  id: id,
  caseId: caseId,
  startsAt: startsAt,
  vet: vet,
  reminderLeadMinutes: leadMinutes,
  reminderMuted: muted,
  attendedAt: attendedAt,
  cancelledAt: cancelledAt,
);

List<PlannedReminder> _planAppointments(
  List<VetAppointment> appointments, {
  List<Case>? cases,
  Map<String, String?> animalNames = const {'a-c1': 'Bella'},
  Duration defaultLead = const Duration(days: 1),
}) => planVetAppointmentReminders(
  l10n: _l10n,
  appointments: appointments,
  casesById: {
    for (final c in cases ?? [_case('c1', number: '2026-001')]) c.id: c,
  },
  animalNameById: animalNames,
  defaultLead: defaultLead,
  now: _now,
);

void main() {
  // The appointment notification body formats a date through intl, which needs
  // its locale symbols loaded (bootstrap does this in the real app).
  setUpAll(initializeDateFormatting);
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
    expect(r.channel, ReminderChannel.medication);
    expect(r.fireAtUtc, _now.add(const Duration(hours: 6)));
    expect(r.payload, '/cases/c1');
  });

  test('already-due and overdue rows are skipped — the worklist owns those, '
      'a notification would re-fire on every reconcile', () {
    final planned = _plan([
      _due('m1', nextDue: _now),
      _due('m2', nextDue: _now.subtract(const Duration(hours: 2))),
      // No next-due at all. Since federfall-082v that is a deliberate signal
      // from the view, not just an absent value: the plan is still running but
      // its next dose would fall past its own end, so there is nothing to fire.
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

  test('a namespace yields a different id, and the un-namespaced hash is '
      'pinned so existing medication reminders can never silently move', () {
    expect(
      reminderNotificationId('v1', namespace: vetAppointmentReminderNamespace),
      isNot(reminderNotificationId('v1')),
    );
    // Literal, on purpose: this value is baked into every reminder
    // federfall-3uz ever scheduled.
    expect(reminderNotificationId('m1'), 338587627);
  });

  group('planVetAppointmentReminders', () {
    test('a future appointment fires one lead time ahead of its start', () {
      final planned = _planAppointments([
        _appointment('v1', startsAt: _now.add(const Duration(days: 3))),
      ]);

      expect(planned, hasLength(1));
      final r = planned.single;
      expect(
        r.id,
        reminderNotificationId(
          'v1',
          namespace: vetAppointmentReminderNamespace,
        ),
      );
      expect(r.channel, ReminderChannel.appointment);
      expect(r.title, 'Vet appointment: Dr. Vogel');
      // It fires ahead of the appointment, so the body has to name the moment.
      expect(r.body, contains('2026-001 · Bella'));
      expect(r.body, contains('Jun'));
      expect(r.fireAtUtc, _now.add(const Duration(days: 2)));
      expect(r.payload, '/cases/c1');
    });

    test('a record-level lead beats the device default', () {
      final planned = _planAppointments([
        _appointment(
          'v1',
          startsAt: _now.add(const Duration(days: 3)),
          leadMinutes: 60,
        ),
      ]);
      expect(
        planned.single.fireAtUtc,
        _now.add(const Duration(days: 3)).subtract(const Duration(hours: 1)),
      );
    });

    test('a lead no picker offers is still honoured — the field is minutes, '
        'not an enum ordinal', () {
      final planned = _planAppointments([
        _appointment(
          'v1',
          startsAt: _now.add(const Duration(days: 3)),
          leadMinutes: 45,
        ),
      ]);
      expect(
        planned.single.fireAtUtc,
        _now.add(const Duration(days: 3)).subtract(const Duration(minutes: 45)),
      );
    });

    test('a muted appointment is skipped even with a lead and a default', () {
      final planned = _planAppointments([
        _appointment(
          'v1',
          startsAt: _now.add(const Duration(days: 3)),
          leadMinutes: 60,
          muted: true,
        ),
      ]);
      expect(planned, isEmpty);
    });

    test('an appointment whose lead window has already closed is skipped — a '
        'past zonedSchedule fires immediately on Android', () {
      final planned = _planAppointments([
        _appointment('v1', startsAt: _now.add(const Duration(hours: 6))),
      ]);
      expect(planned, isEmpty);
    });

    test('attended and cancelled appointments are skipped', () {
      final planned = _planAppointments([
        _appointment(
          'v1',
          startsAt: _now.add(const Duration(days: 3)),
          attendedAt: _now,
        ),
        _appointment(
          'v2',
          startsAt: _now.add(const Duration(days: 3)),
          cancelledAt: _now,
        ),
      ]);
      expect(planned, isEmpty);
    });

    test('an appointment with no start, or on an out-of-scope case, is '
        'skipped', () {
      expect(_planAppointments([_appointment('v1')]), isEmpty);
      expect(
        _planAppointments([
          _appointment(
            'v1',
            caseId: 'other',
            startsAt: _now.add(const Duration(days: 3)),
          ),
        ]),
        isEmpty,
      );
    });

    test('a missing or empty practice falls back to a generic title', () {
      for (final vet in [null, '']) {
        final planned = _planAppointments([
          _appointment(
            'v1',
            startsAt: _now.add(const Duration(days: 3)),
            vet: vet,
          ),
        ]);
        expect(planned.single.title, 'Vet appointment', reason: 'vet: $vet');
      }
    });

    test('an unnumbered, unnamed case falls back to the placeholder', () {
      final planned = _planAppointments(
        [_appointment('v1', startsAt: _now.add(const Duration(days: 3)))],
        cases: [_case('c1')],
        animalNames: const {},
      );
      expect(planned.single.body, contains('Unnumbered case'));
    });
  });

  group('mergeReminders', () {
    PlannedReminder r(String id, ReminderChannel channel, int hours) =>
        PlannedReminder(
          id: reminderNotificationId(id),
          channel: channel,
          title: id,
          body: id,
          fireAtUtc: _now.add(Duration(hours: hours)),
          payload: '/cases/c1',
        );

    test('returns everything, soonest first, when under the cap', () {
      final merged = mergeReminders(
        appointments: [r('v1', ReminderChannel.appointment, 10)],
        medications: [
          r('m2', ReminderChannel.medication, 20),
          r('m1', ReminderChannel.medication, 1),
        ],
      );
      expect(merged.map((x) => x.title), ['m1', 'v1', 'm2']);
    });

    test('appointments are reserved first: a dense dose schedule cannot evict '
        'the appointment reminder furthest out', () {
      final merged = mergeReminders(
        appointments: [r('v1', ReminderChannel.appointment, 72)],
        medications: [
          for (var i = 0; i < 10; i++) r('m-$i', ReminderChannel.medication, i),
        ],
        max: 3,
      );
      expect(merged, hasLength(3));
      expect(
        merged.where((x) => x.channel == ReminderChannel.appointment),
        hasLength(1),
      );
    });

    test('appointments alone can fill the cap, dropping every dose', () {
      final merged = mergeReminders(
        appointments: [
          for (var i = 0; i < 5; i++) r('v-$i', ReminderChannel.appointment, i),
        ],
        medications: [r('m1', ReminderChannel.medication, 1)],
        max: 2,
      );
      expect(merged, hasLength(2));
      expect(
        merged.every((x) => x.channel == ReminderChannel.appointment),
        isTrue,
      );
    });

    test('merged ids are all distinct — an equal id silently replaces', () {
      final merged = mergeReminders(
        appointments: [r('v1', ReminderChannel.appointment, 5)],
        medications: [
          r('m1', ReminderChannel.medication, 1),
          r('m2', ReminderChannel.medication, 2),
        ],
      );
      expect(merged.map((x) => x.id).toSet(), hasLength(merged.length));
    });
  });

  test('the two channels have distinct ids', () {
    expect(
      ReminderChannel.values.map((c) => c.channelId).toSet(),
      hasLength(ReminderChannel.values.length),
    );
  });
}
