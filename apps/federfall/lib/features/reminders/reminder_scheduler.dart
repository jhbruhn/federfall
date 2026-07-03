import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/features/reminders/reminder_plan.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:timezone/timezone.dart' as tz;

part 'reminder_scheduler.g.dart';

/// Thin seam over the platform notifications plugin so the reminder logic
/// stays testable (the plugin talks to method channels, which don't exist in
/// widget tests) and the web build gets a clean no-op.
abstract class ReminderScheduler {
  /// Initialises the underlying plugin once. [onSelect] receives the tapped
  /// notification's payload (an in-app location) — including the one that
  /// launched the app from a terminated state. Safe to call repeatedly.
  Future<void> init({required void Function(String payload) onSelect});

  /// Asks the OS for notification permission (Android 13+ POST_NOTIFICATIONS,
  /// iOS authorization). Returns whether notifications may be shown.
  Future<bool> requestPermissions();

  /// Replaces everything currently scheduled with [reminders]. Reconcile-style
  /// on purpose: the desired set is recomputed from server state each time, so
  /// wholesale replacement can never leak a stale reminder for an ended or
  /// handed-off prescription.
  Future<void> replaceAll(List<PlannedReminder> reminders);

  /// Cancels every scheduled reminder (sign-out, reminders toggled off).
  Future<void> cancelAll();
}

/// No-op scheduler for platforms without local notification scheduling (web).
class NoopReminderScheduler implements ReminderScheduler {
  @override
  Future<void> init({required void Function(String payload) onSelect}) async {}

  @override
  Future<bool> requestPermissions() async => false;

  @override
  Future<void> replaceAll(List<PlannedReminder> reminders) async {}

  @override
  Future<void> cancelAll() async {}
}

/// [ReminderScheduler] over `flutter_local_notifications`: notifications are
/// handed to the OS (zoned schedule), so they fire with the app backgrounded
/// or closed.
class LocalReminderScheduler implements ReminderScheduler {
  final _plugin = FlutterLocalNotificationsPlugin();
  var _initialized = false;

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  IOSFlutterLocalNotificationsPlugin? get _ios =>
      _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();

  @override
  Future<void> init({required void Function(String payload) onSelect}) async {
    if (_initialized) return;
    _initialized = true;

    // Permissions are requested explicitly when the user enables the toggle,
    // not on app start.
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) onSelect(payload);
      },
    );

    // A tap on a notification while the app was terminated launches the app
    // instead of reaching the callback above — replay it once here.
    final launch = await _plugin.getNotificationAppLaunchDetails();
    final payload = launch?.notificationResponse?.payload;
    if ((launch?.didNotificationLaunchApp ?? false) &&
        payload != null &&
        payload.isNotEmpty) {
      onSelect(payload);
    }
  }

  @override
  Future<bool> requestPermissions() async {
    final android = _android;
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    return await _ios?.requestPermissions(alert: true, sound: true) ?? true;
  }

  @override
  Future<void> replaceAll(List<PlannedReminder> reminders) async {
    await _plugin.cancelAll();

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'medication_reminders',
        // The channel name shows up in Android's notification settings.
        // German to match the app's fixed UI language (app.dart).
        'Medikamenten-Erinnerungen',
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
      ),
    );

    for (final r in reminders) {
      try {
        await _plugin.zonedSchedule(
          id: r.id,
          title: r.title,
          body: r.body,
          payload: r.payload,
          // The due moment is an absolute instant; scheduling it in UTC fires
          // at the right time in any device timezone, DST included (zones
          // only matter for recurring `matchDateTimeComponents` schedules).
          scheduledDate: tz.TZDateTime.from(r.dueAtUtc, tz.UTC),
          notificationDetails: details,
          // Inexact on purpose: exact delivery needs Android's "Alarms &
          // reminders" special access, which can only be granted on a system
          // settings page — a jarring detour for no clinical gain (doses are
          // interval-based; the OS batching window of ~10-15 min is fine).
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      } on Object catch (error, stackTrace) {
        // One unschedulable reminder (e.g. a permission revoked mid-flight)
        // must not take down the rest of the batch.
        reportCaughtError(
          error,
          stackTrace,
          context: 'Scheduling medication reminder failed',
        );
      }
    }
  }

  @override
  Future<void> cancelAll() => _plugin.cancelAll();
}

/// The platform-appropriate scheduler. keepAlive: the underlying plugin is a
/// process-wide singleton and must be initialised exactly once.
@Riverpod(keepAlive: true)
ReminderScheduler reminderScheduler(Ref ref) =>
    kIsWeb ? NoopReminderScheduler() : LocalReminderScheduler();
