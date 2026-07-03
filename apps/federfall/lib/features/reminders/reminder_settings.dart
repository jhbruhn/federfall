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
