import 'package:federfall/features/cases/vet_appointments/vet_appointment_calendar.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart' hide Finder;

final AppLocalizations _l10n = lookupAppLocalizations(const Locale('en'));

/// 2026-06-25 09:00 UTC, comfortably in the future of nothing in particular —
/// the mapper has no notion of "now", so any instant will do.
final _startsAt = DateTime.utc(2026, 6, 25, 9);

VetAppointment _appointment({
  DateTime? startsAt,
  String? vet,
  String? reason,
  int? leadMinutes,
  bool muted = false,
}) => VetAppointment(
  id: 'va1',
  caseId: 'c1',
  startsAt: startsAt ?? _startsAt,
  vet: vet,
  reason: reason,
  reminderLeadMinutes: leadMinutes,
  reminderMuted: muted,
);

void main() {
  group('vetAppointmentCalendarEvent', () {
    test('maps practice, bird and reason onto the entry', () {
      final event = vetAppointmentCalendarEvent(
        l10n: _l10n,
        appointment: _appointment(vet: 'Praxis Müller', reason: 'Flügel'),
        caseTitle: '2026-001 · Bella',
        defaultLead: const Duration(days: 1),
      )!;

      expect(event.title, 'Vet appointment: Praxis Müller');
      expect(event.start, _startsAt.toLocal());
      // No duration on the record: the fixed slot is what gets blocked.
      expect(
        event.end,
        _startsAt.toLocal().add(kVetAppointmentCalendarDuration),
      );
      expect(event.description, '2026-001 · Bella\n\nFlügel');
    });

    test('falls back to the generic title without a practice', () {
      final event = vetAppointmentCalendarEvent(
        l10n: _l10n,
        appointment: _appointment(vet: ''),
        caseTitle: '2026-001',
        defaultLead: const Duration(days: 1),
      )!;

      expect(event.title, 'Vet appointment');
      // Nothing dangling: no reason means the description is the bird alone.
      expect(event.description, '2026-001');
    });

    test('uses the device default lead, and the record override over it', () {
      const defaultLead = Duration(days: 1);

      expect(
        vetAppointmentCalendarEvent(
          l10n: _l10n,
          appointment: _appointment(),
          caseTitle: 'c',
          defaultLead: defaultLead,
        )!.reminder,
        defaultLead,
      );
      expect(
        vetAppointmentCalendarEvent(
          l10n: _l10n,
          appointment: _appointment(leadMinutes: 120),
          caseTitle: 'c',
          defaultLead: defaultLead,
        )!.reminder,
        const Duration(hours: 2),
      );
    });

    test('carries no reminder when the appointment is muted', () {
      final event = vetAppointmentCalendarEvent(
        l10n: _l10n,
        // A mute keeps its previously chosen lead on the record; the mute has
        // to win over it, not the other way round.
        appointment: _appointment(leadMinutes: 120, muted: true),
        caseTitle: 'c',
        defaultLead: const Duration(days: 1),
      )!;

      expect(event.reminder, isNull);
    });

    test('is null without a start — there is no event without a moment', () {
      expect(
        vetAppointmentCalendarEvent(
          l10n: _l10n,
          appointment: const VetAppointment(id: 'va1', caseId: 'c1'),
          caseTitle: 'c',
          defaultLead: const Duration(days: 1),
        ),
        isNull,
      );
    });
  });
}
