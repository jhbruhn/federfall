import 'package:federfall/features/printing/printer_settings.dart';

/// Overrides `printerSettingsProvider` with a fixed, in-memory value instead
/// of touching real `shared_preferences` — screens that only READ the
/// current settings (case-detail's print button, the profile section's
/// display) don't need real persistence to be exercised, only the
/// provider's future/value resolving to something. Calling
/// `SharedPreferences.setMockInitialValues` from a widget test that also
/// depends on other realtime/async provider chains has been flaky in this
/// codebase (federfall-i0wq) — overriding the app-level abstraction directly
/// sidesteps that entirely. Persistence itself (setDevice/setPaperSize
/// actually writing through) is covered by printer_settings_test.dart and
/// printer_config_sheet_test.dart, which DO need the real notifier.
class FakePrinterSettingsNotifier extends PrinterSettingsNotifier {
  FakePrinterSettingsNotifier(this._initial);

  final PrinterSettings _initial;

  @override
  Future<PrinterSettings> build() async => _initial;
}
