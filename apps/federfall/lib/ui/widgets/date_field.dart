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
    this.enabled = true,
    this.showTime = false,
    super.key,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onPick;
  final VoidCallback? onClear;
  final String? placeholder;
  final bool enabled;

  /// Whether to append the time of day to the displayed value.
  final bool showTime;

  @override
  Widget build(BuildContext context) {
    final materialL10n = MaterialLocalizations.of(context);
    final text = value == null
        ? (placeholder ?? '')
        : formatDateMaybeTime(materialL10n, value!, withTime: showTime);
    return InkWell(
      onTap: enabled ? onPick : null,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
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

/// Formats [value] as a medium date, optionally followed by its time of day.
/// [value] is expected to already be in local time.
String formatDateMaybeTime(
  MaterialLocalizations materialL10n,
  DateTime value, {
  bool withTime = false,
}) {
  final date = materialL10n.formatMediumDate(value);
  if (!withTime) return date;
  final time = materialL10n.formatTimeOfDay(TimeOfDay.fromDateTime(value));
  return '$date, $time';
}

/// Formats a chronology event's timestamp for display. PocketBase stores UTC
/// (and `MaterialLocalizations` does not convert time zones), so this converts
/// to local time first; pass any timeline date through here so every entry
/// shares one time-zone-correct treatment. Returns '' for null so a tile can
/// simply omit the header.
String formatEventDate(
  MaterialLocalizations materialL10n,
  DateTime? value, {
  bool withTime = false,
}) {
  if (value == null) return '';
  return formatDateMaybeTime(
    materialL10n,
    value.toLocal(),
    withTime: withTime,
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
