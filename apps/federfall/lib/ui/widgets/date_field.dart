import 'package:flutter/material.dart';

/// A tappable, read-only date field rendered like the app's text inputs, with
/// an optional clear action for nullable dates. Tapping it opens the caller's
/// date (or date+time) picker via [onPick]. Set [showTime] to also render the
/// time of day — pair it with [pickDateTime] in the caller.
class DateField extends StatelessWidget {
  const DateField({
    required this.label,
    required this.value,
    required this.onPick,
    this.onClear,
    this.placeholder,
    this.errorText,
    this.enabled = true,
    this.showTime = false,
    super.key,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onPick;
  final VoidCallback? onClear;
  final String? placeholder;
  final String? errorText;
  final bool enabled;

  /// Whether to append the time of day to the displayed value.
  final bool showTime;

  @override
  Widget build(BuildContext context) {
    final materialL10n = MaterialLocalizations.of(context);
    final text = value == null
        ? (placeholder ?? '')
        : formatLocalDate(materialL10n, value, withTime: showTime);
    return InkWell(
      onTap: enabled ? onPick : null,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          errorText: errorText,
          prefixIcon: Icon(
            showTime ? Icons.schedule_outlined : Icons.event_outlined,
          ),
          suffixIcon: value != null && enabled && onClear != null
              ? IconButton(icon: const Icon(Icons.clear), onPressed: onClear)
              : null,
        ),
        child: Text(text),
      ),
    );
  }
}

/// Which of Material's date shapes [formatLocalDate] renders.
enum DateStyle {
  /// Material's medium form — "Wed, Jun 2" in English. Carries a weekday but
  /// no year, so it reads best for something the surrounding screen already
  /// places in time.
  medium,

  /// Material's short form — "6/2/2026" in English. Numeric and, unlike
  /// [medium], it carries the year, which anything spanning seasons needs.
  short,

  /// Material's compact form — "06/02/2026" in English, "02.06.2026" in
  /// German. All-numeric and fixed-width, which is what a chart axis wants:
  /// [short] spells the month out in German ("2. März 2026") and is twice as
  /// wide as the column an axis label gets.
  compact,
}

/// Formats [value] **in the reader's local time zone**, optionally followed by
/// its time of day. Returns '' for null so a tile can simply omit the line.
///
/// This is the only place in the app that turns a `DateTime` into a date
/// string, and it exists because the naive spelling is wrong: PocketBase
/// stores UTC, `MaterialLocalizations` formats whatever fields it is handed,
/// and it does not convert time zones. So `formatMediumDate(case.admittedAt)`
/// silently renders the UTC calendar day — which in CET/CEST is the *previous*
/// day for anything logged after 22:00 UTC (federfall-yok0). Converting here,
/// once, is what makes that unrepresentable; `toLocal()` is idempotent, so
/// passing a value that is already local (form state, a picker result) is
/// correct too and needs no thought at the call site.
///
/// `date_field_test.dart` fails the build if any other file under `lib/`
/// formats a date directly.
String formatLocalDate(
  MaterialLocalizations materialL10n,
  DateTime? value, {
  bool withTime = false,
  DateStyle style = DateStyle.medium,
}) {
  if (value == null) return '';
  final local = value.toLocal();
  final date = switch (style) {
    DateStyle.medium => materialL10n.formatMediumDate(local),
    DateStyle.short => materialL10n.formatShortDate(local),
    DateStyle.compact => materialL10n.formatCompactDate(local),
  };
  if (!withTime) return date;
  final time = materialL10n.formatTimeOfDay(TimeOfDay.fromDateTime(local));
  return '$date, $time';
}

/// Opens a date picker seeded at [initial] (local), returning the picked
/// **local** [DateTime], or `null` if cancelled.
Future<DateTime?> pickDate(
  BuildContext context, {
  required DateTime initial,
  DateTime? firstDate,
  DateTime? lastDate,
}) {
  return showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: firstDate ?? DateTime(2000),
    lastDate: lastDate ?? DateTime.now(),
  );
}

/// Chains a date then a time picker, returning the combined **local**
/// [DateTime], or `null` if the date step was cancelled. [initial] (local)
/// seeds both steps; cancelling only the time step keeps [initial]'s time.
Future<DateTime?> pickDateTime(
  BuildContext context, {
  required DateTime initial,
  DateTime? firstDate,
  DateTime? lastDate,
}) async {
  final date = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: firstDate ?? DateTime(2000),
    lastDate: lastDate ?? DateTime.now(),
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initial),
  );
  final t = time ?? TimeOfDay.fromDateTime(initial);
  return DateTime(date.year, date.month, date.day, t.hour, t.minute);
}
