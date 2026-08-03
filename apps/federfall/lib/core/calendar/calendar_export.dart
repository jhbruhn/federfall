import 'package:federfall/core/calendar/calendar_export_stub.dart'
    if (dart.library.io) 'package:federfall/core/calendar/calendar_export_native.dart'
    as platform;
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'calendar_export.g.dart';

/// One calendar entry to hand to the OS — a plain, package-agnostic
/// description, NOT a re-export of `package:add_2_calendar`'s own `Event`
/// (federfall-v3a8).
///
/// That package's `Event` unconditionally `import`s `dart:io` (its `toJson`
/// branches on `Platform.isIOS`), so importing it from any file the web build
/// can reach breaks web compilation outright — a runtime `kIsWeb` guard cannot
/// help, since the front end resolves the whole import graph first. Same trap,
/// and the same escape hatch, as `printing/printer_service.dart`: the plugin is
/// imported only from calendar_export_native.dart, which this file pulls in
/// conditionally on `dart.library.io` — absent on both web targets (dart2js and
/// dart2wasm) and present on every platform this app ships natively.
@immutable
class CalendarEvent {
  const CalendarEvent({
    required this.title,
    required this.start,
    required this.end,
    this.description,
    this.reminder,
  });

  final String title;

  /// Local wall-clock start and end. Only the absolute instant is handed over
  /// (epoch millis), so the calendar app resolves the display timezone itself.
  final DateTime start;
  final DateTime end;

  final String? description;

  /// How far ahead of [start] the calendar should alert, if the platform lets
  /// us prescribe that — see [CalendarExporter.add].
  final Duration? reminder;

  @override
  bool operator ==(Object other) =>
      other is CalendarEvent &&
      other.title == title &&
      other.start == start &&
      other.end == end &&
      other.description == description &&
      other.reminder == reminder;

  @override
  int get hashCode => Object.hash(title, start, end, description, reminder);
}

/// Thin seam over the platform calendar plugin, so callers stay testable (the
/// plugin talks to a method channel, which doesn't exist in widget tests) and
/// the web build gets a clean no-op.
abstract class CalendarExporter {
  /// Whether this platform can hand an event to a calendar app at all. False on
  /// web — callers must hide the affordance rather than offer an action that
  /// cannot work.
  bool get isSupported;

  /// Opens the OS calendar's new-event editor prefilled from [event].
  ///
  /// Nothing is written behind the user's back: this is a hand-off, the user
  /// confirms (and may edit) the entry in their calendar app. Consequently
  /// there is no event identity to update later — exporting the same
  /// appointment twice creates two entries, which is why the appointment sheet
  /// does not offer this automatically.
  ///
  /// Returns whether the entry was taken up. False means "nothing was added",
  /// which covers both "no calendar app on this device" (Android, where the
  /// intent resolves to nothing) and "the user cancelled the editor" (iOS) —
  /// the platforms genuinely cannot distinguish those, so callers must report
  /// it neutrally.
  ///
  /// [CalendarEvent.reminder] is honoured on iOS only (an `EKAlarm` on the
  /// created event). Android's insert intent carries no alarm extra, so there
  /// the calendar applies its own default notice.
  Future<bool> add(CalendarEvent event);
}

/// The platform-appropriate exporter.
@riverpod
CalendarExporter calendarExporter(Ref ref) => platform.createCalendarExporter();
