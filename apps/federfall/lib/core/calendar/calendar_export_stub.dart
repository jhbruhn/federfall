import 'package:federfall/core/calendar/calendar_export.dart';

/// The web build's exporter: there is no OS calendar to hand an event to, so it
/// reports itself unsupported and never claims to have added anything. See
/// calendar_export.dart for why the real implementation cannot live here.
CalendarExporter createCalendarExporter() =>
    const _UnsupportedCalendarExporter();

class _UnsupportedCalendarExporter implements CalendarExporter {
  const _UnsupportedCalendarExporter();

  @override
  bool get isSupported => false;

  @override
  Future<bool> add(CalendarEvent event) async => false;
}
