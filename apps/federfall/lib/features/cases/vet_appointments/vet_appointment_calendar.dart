import 'package:federfall/core/calendar/calendar_export.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_models/federfall_models.dart';

/// How long a vet appointment blocks in the calendar (federfall-v3a8).
///
/// The record has a start and no duration, and inventing a backend field for
/// something the carer can drag in their own calendar app is not worth it. Half
/// an hour is the usual consultation slot; the user confirms (and can adjust)
/// the entry before it is saved anyway.
const Duration kVetAppointmentCalendarDuration = Duration(minutes: 30);

/// Builds the calendar entry for [appointment], or null when it has no start —
/// there is no event without a moment.
///
/// [caseTitle] is the case number and bird name (see `caseTitleLabel`); it goes
/// into the description rather than the summary, because in a day view "which
/// practice, when" is what the carer is scanning for and the bird is the detail
/// they open the entry to check.
CalendarEvent? vetAppointmentCalendarEvent({
  required AppLocalizations l10n,
  required VetAppointment appointment,
  required String caseTitle,
  required Duration defaultLead,
}) {
  final startsAt = appointment.startsAt?.toLocal();
  if (startsAt == null) return null;

  final vet = appointment.vet;
  final reason = appointment.reason;

  return CalendarEvent(
    // Deliberately the same sentence the reminder notification uses: a carer
    // who gets both should recognise them as one appointment, not two things.
    title: vet == null || vet.isEmpty
        ? l10n.vetAppointmentReminderTitle
        : l10n.vetAppointmentReminderTitleWithVet(vet),
    start: startsAt,
    end: startsAt.add(kVetAppointmentCalendarDuration),
    description: [
      caseTitle,
      if (reason != null && reason.isNotEmpty) reason,
    ].join('\n\n'),
    // Mirrors the app's own reminder so the calendar gives notice at the same
    // moment: the record's override, else the device default, and nothing at
    // all when this appointment's reminder is muted. Deliberately NOT gated on
    // the device-wide appointment-reminder switch — someone who turned the
    // app's notifications off in favour of their calendar is precisely who
    // exports this, and an alarm-less entry would leave them with no notice at
    // all. Muting one appointment is a statement about that appointment, so
    // that one does carry over. Honoured on iOS only — see
    // [CalendarExporter.add].
    reminder: appointment.reminderMuted
        ? null
        : (appointment.reminderLeadMinutes == null
              ? defaultLead
              : Duration(minutes: appointment.reminderLeadMinutes!)),
  );
}
