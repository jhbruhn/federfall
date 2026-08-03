import 'package:federfall/l10n/l10n.dart';

/// The lead times offered for appointment reminders (federfall-fnpo), shared by
/// the device default in Profile and the per-appointment override in the
/// appointment sheet so the two can never drift apart.
///
/// Deliberately a short, coarse ladder rather than a free-form duration field:
/// nobody needs 47 minutes of notice, and a picker beats a numeric input on a
/// phone in a loft.
const List<Duration> kReminderLeadChoices = [
  Duration(hours: 1),
  Duration(hours: 3),
  Duration(hours: 12),
  Duration(days: 1),
  Duration(days: 2),
];

/// Labels a lead time, e.g. "3 Std. vorher" / "1 Tag vorher".
///
/// Any duration formats, not just the [kReminderLeadChoices] entries — a lead
/// written by a newer client with a longer ladder still renders.
String reminderLeadLabel(AppLocalizations l10n, Duration lead) =>
    lead.inHours % 24 == 0 && lead.inHours >= 24
    ? l10n.reminderLeadDays(lead.inDays)
    : l10n.reminderLeadHours(lead.inHours);
