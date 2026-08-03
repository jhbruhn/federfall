import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'reminder_settings.g.dart';

/// Whether the user wants local medication-due reminders on this device
/// (federfall-3uz). Off by default — enabling is the moment to ask for the
/// OS notification permission, so it must be a deliberate opt-in. Persisted
/// per device (reminders are scheduled on-device, so the choice is too).
@Riverpod(keepAlive: true)
class MedicationRemindersEnabled extends _$MedicationRemindersEnabled {
  static const _key = 'medication_reminders_enabled';

  @override
  Future<bool> build() async =>
      (await SharedPreferences.getInstance()).getBool(_key) ?? false;

  Future<void> set({required bool enabled}) async {
    await (await SharedPreferences.getInstance()).setBool(_key, enabled);
    state = AsyncData(enabled);
  }
}

/// Whether the user wants to be reminded ahead of vet appointments on this
/// device (federfall-fnpo).
///
/// Separate from [MedicationRemindersEnabled] on purpose: a carer who finds
/// dose pings naggy may still want appointment notice, and the two land in
/// separate Android channels so the OS can mute one without the other. Off by
/// default, for the same reason the medication switch is.
@Riverpod(keepAlive: true)
class AppointmentRemindersEnabled extends _$AppointmentRemindersEnabled {
  static const _key = 'appointment_reminders_enabled';

  @override
  Future<bool> build() async =>
      (await SharedPreferences.getInstance()).getBool(_key) ?? false;

  Future<void> set({required bool enabled}) async {
    await (await SharedPreferences.getInstance()).setBool(_key, enabled);
    state = AsyncData(enabled);
  }
}

/// How far ahead of an appointment to remind, by default (federfall-fnpo).
///
/// Per device, like the switches — a reminder is scheduled on-device, so the
/// choice belongs to the device. An individual appointment may override this
/// (`VetAppointment.reminderLeadMinutes`), which is stored on the record and so
/// travels with a handoff.
@Riverpod(keepAlive: true)
class AppointmentReminderLead extends _$AppointmentReminderLead {
  static const _key = 'appointment_reminder_lead_minutes';

  /// One day ahead: enough notice to rearrange a morning, short enough that the
  /// appointment is still the next thing on the carer's mind.
  static const Duration defaultLead = Duration(days: 1);

  @override
  Future<Duration> build() async {
    final minutes = (await SharedPreferences.getInstance()).getInt(_key);
    // A non-positive stored value would mean "remind me at or after the
    // appointment", which is not a reminder. Nothing writes one, so treat it as
    // corrupt and fall back rather than silently scheduling nothing.
    if (minutes == null || minutes <= 0) return defaultLead;
    return Duration(minutes: minutes);
  }

  Future<void> set(Duration lead) async {
    await (await SharedPreferences.getInstance()).setInt(_key, lead.inMinutes);
    state = AsyncData(lead);
  }
}
