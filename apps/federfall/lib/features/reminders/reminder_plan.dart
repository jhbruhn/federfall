import 'package:federfall/features/cases/medications/medications_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/routing/app_routes.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/foundation.dart';

/// Which OS notification channel a reminder belongs to (federfall-fnpo).
///
/// Two channels on purpose: Android's mute state and importance are per channel
/// and importance cannot be changed after creation, so a carer who wants
/// appointment notice but not dose pings can only get that if the two live
/// apart.
enum ReminderChannel {
  medication('medication_reminders', 'Medikamenten-Erinnerungen'),
  appointment('appointment_reminders', 'Termin-Erinnerungen');

  const ReminderChannel(this.channelId, this.channelName);

  /// Stable forever — renaming a channel id orphans the user's mute choice.
  final String channelId;

  /// Shown in Android's notification settings. Hardcoded German: this string
  /// lives in the OS, not in the app's widget tree, so there is no
  /// `AppLocalizations` at the point Android asks for it, and re-creating the
  /// channel per locale change is not worth a settings entry the carer sees
  /// once. Every user-facing string inside the app is localized as usual.
  final String channelName;
}

/// One OS-level notification to schedule (federfall-3uz, federfall-fnpo): a
/// medication dose coming due, or a vet appointment coming up. The id is stable
/// per source record so rescheduling replaces the previous reminder instead of
/// stacking a duplicate.
@immutable
class PlannedReminder {
  const PlannedReminder({
    required this.id,
    required this.channel,
    required this.title,
    required this.body,
    required this.fireAtUtc,
    required this.payload,
  });

  /// Stable notification id, see [reminderNotificationId].
  final int id;

  /// Which OS channel to post on.
  final ReminderChannel channel;

  final String title;
  final String body;

  /// The moment to fire, as an absolute UTC instant.
  ///
  /// For a dose this *is* the due moment; for an appointment it is the
  /// appointment time minus the configured lead — hence "fire", not "due".
  final DateTime fireAtUtc;

  /// In-app location to open on tap (the case detail).
  final String payload;

  @override
  bool operator ==(Object other) =>
      other is PlannedReminder &&
      other.id == id &&
      other.channel == channel &&
      other.title == title &&
      other.body == body &&
      other.fireAtUtc == fireAtUtc &&
      other.payload == payload;

  @override
  int get hashCode => Object.hash(id, channel, title, body, fireAtUtc, payload);
}

/// Namespace mixed into the hash for vet-appointment reminder ids.
///
/// Not strictly required — PocketBase record ids are globally unique, so the
/// two sources already hash distinct inputs — but both share one flat id space
/// in which an equal id means "replace", so keeping them independent costs
/// nothing and removes a whole class of silent loss.
const String vetAppointmentReminderNamespace = 'vet:';

/// The OS budget for pending local notifications.
///
/// iOS keeps at most 64 pending requests per app and its behaviour past that is
/// unspecified; Android has no documented cap but every pending alarm is real
/// work. 60 leaves headroom and sits above any realistic caseload.
const int maxScheduledReminders = 60;

/// A stable 31-bit notification id derived from a record id (FNV-1a).
///
/// Platform notification ids are ints; hashing the record id — rather than
/// using `String.hashCode`, which is not guaranteed stable across runs — makes
/// every (re)schedule of the same record land on the same slot, so updating a
/// reminder replaces the old one. [namespace] defaults to empty, which keeps
/// medication ids byte-identical to what federfall-3uz shipped.
int reminderNotificationId(String recordId, {String namespace = ''}) {
  var hash = 0x811c9dc5;
  for (final unit in '$namespace$recordId'.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash;
}

/// Builds the medication reminders to have scheduled as of [now]: one per
/// prescription whose server-computed `next_due` lies in the future.
///
/// Deliberately skips anything already due or overdue — those are visible on
/// the worklist, and firing them on every reconcile (app start, each dose
/// logged elsewhere) would nag rather than remind. A reminder only makes
/// sense for a moment that hasn't arrived yet.
List<PlannedReminder> planMedicationReminders({
  required AppLocalizations l10n,
  required List<MedicationDue> medicationsDue,
  required Map<String, Case> casesById,
  required Map<String, String?> animalNameById,
  required DateTime now,
}) {
  final planned = <PlannedReminder>[];
  for (final md in medicationsDue) {
    final due = md.nextDue;
    if (due == null || !due.isAfter(now)) continue;
    final c = casesById[md.caseId];
    if (c == null) continue;

    final dose = formatDose(l10n, md.dose, md.doseUnit);
    final body = [
      if (dose.isNotEmpty) dose,
      _caseTitle(l10n, c, animalNameById),
    ].join(' — ');

    planned.add(
      PlannedReminder(
        id: reminderNotificationId(md.id),
        channel: ReminderChannel.medication,
        title: l10n.medicationReminderTitle(md.drug),
        body: body,
        fireAtUtc: due.toUtc(),
        payload: AppRoutes.caseDetail(md.caseId),
      ),
    );
  }
  return planned;
}

/// Builds the vet-appointment reminders to have scheduled as of [now]: one per
/// upcoming, unresolved appointment, fired [defaultLead] ahead of its start
/// unless the record overrides that (federfall-fnpo).
///
/// Lead resolution: `reminderMuted` wins over everything, then the record's
/// `reminderLeadMinutes`, then [defaultLead].
///
/// Like [planMedicationReminders] this refuses to schedule a moment that has
/// already passed — Android fires a past `zonedSchedule` immediately, so an
/// appointment whose lead window has closed would ping on every single app
/// start until the appointment is resolved.
List<PlannedReminder> planVetAppointmentReminders({
  required AppLocalizations l10n,
  required List<VetAppointment> appointments,
  required Map<String, Case> casesById,
  required Map<String, String?> animalNameById,
  required Duration defaultLead,
  required DateTime now,
}) {
  final planned = <PlannedReminder>[];
  for (final a in appointments) {
    // Attended or cancelled: the visit is settled. The repository query already
    // excludes both, but the plan has to be correct on its own inputs — the
    // case bundle is not filtered.
    if (a.attendedAt != null || a.cancelledAt != null) continue;
    if (a.reminderMuted) continue;

    final startsAt = a.startsAt;
    if (startsAt == null) continue;

    // Plain minutes, not an enum ordinal, so a lead written by a client with a
    // different ladder still resolves here.
    final lead = a.reminderLeadMinutes == null
        ? defaultLead
        : Duration(minutes: a.reminderLeadMinutes!);
    final fireAt = startsAt.subtract(lead);
    if (!fireAt.isAfter(now)) continue;

    final c = casesById[a.caseId];
    if (c == null) continue;

    final vet = a.vet;
    planned.add(
      PlannedReminder(
        id: reminderNotificationId(
          a.id,
          namespace: vetAppointmentReminderNamespace,
        ),
        channel: ReminderChannel.appointment,
        title: vet == null || vet.isEmpty
            ? l10n.vetAppointmentReminderTitle
            : l10n.vetAppointmentReminderTitleWithVet(vet),
        // Unlike a dose reminder this fires AHEAD of the moment it is about, so
        // the body has to carry the appointment's own time — "vet appointment"
        // with no "when" is useless a day out. Local: the carer reads a wall
        // clock, not an instant.
        body: l10n.vetAppointmentReminderBody(
          startsAt.toLocal(),
          _caseTitle(l10n, c, animalNameById),
        ),
        fireAtUtc: fireAt.toUtc(),
        payload: AppRoutes.caseDetail(a.caseId),
      ),
    );
  }
  return planned;
}

/// Folds both reminder sources into the single set handed to the scheduler,
/// soonest first, within [max].
///
/// Appointments are kept whole and medications fill what is left — NOT a plain
/// sort-and-take of the union. Doses recur every few hours, so even a moderate
/// prescription load would fill the budget with the next two days and evict the
/// appointment reminder three days out: the one item a carer cannot reconstruct
/// by opening the app. Appointments are inherently few (one or two per case,
/// future only), so reserving them costs the doses almost nothing.
List<PlannedReminder> mergeReminders({
  required List<PlannedReminder> appointments,
  required List<PlannedReminder> medications,
  int max = maxScheduledReminders,
}) {
  int soonestFirst(PlannedReminder a, PlannedReminder b) =>
      a.fireAtUtc.compareTo(b.fireAtUtc);

  final kept = (appointments.toList()..sort(soonestFirst)).take(max).toList();
  kept.addAll(
    (medications.toList()..sort(soonestFirst)).take(max - kept.length),
  );
  return kept..sort(soonestFirst);
}

/// "2026-001 · Bella" — the case number and the bird's name, whichever exist,
/// falling back to a generic label for an unnumbered, unnamed case.
String _caseTitle(
  AppLocalizations l10n,
  Case c,
  Map<String, String?> animalNameById,
) {
  final name = animalNameById[c.animal];
  final title = [
    ?c.caseNumber,
    if (name != null && name.isNotEmpty) name,
  ].join(' · ');
  return title.isEmpty ? l10n.worklistUnnumberedCase : title;
}
