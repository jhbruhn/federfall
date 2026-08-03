import 'package:add_2_calendar/add_2_calendar.dart' as a2c;
import 'package:federfall/core/calendar/calendar_export.dart';

/// The Android/iOS exporter, and the only file allowed to import
/// `package:add_2_calendar` — see calendar_export.dart.
CalendarExporter createCalendarExporter() => const _PluginCalendarExporter();

class _PluginCalendarExporter implements CalendarExporter {
  const _PluginCalendarExporter();

  @override
  bool get isSupported => true;

  @override
  Future<bool> add(CalendarEvent event) => a2c.Add2Calendar.addEvent2Cal(
    a2c.Event(
      title: event.title,
      description: event.description,
      startDate: event.start,
      endDate: event.end,
      // No `timeZone`: start/end travel as epoch millis, so the instant is
      // already unambiguous, and naming a zone we'd have to guess at (the app
      // never resolves the device's IANA zone id — the reminder scheduler
      // deliberately schedules in UTC) is how an event lands an hour off.
      iosParams: a2c.IOSParams(reminder: event.reminder),
    ),
  );
}
