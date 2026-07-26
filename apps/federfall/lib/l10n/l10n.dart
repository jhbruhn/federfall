import 'package:federfall/l10n/gen/app_localizations.dart';
import 'package:flutter/widgets.dart';

export 'package:federfall/l10n/gen/app_localizations.dart';

extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// The locale the app falls back to when the device asks for a language we do
/// not ship: German is the design language, and every string is written in it
/// first.
///
/// Spelled out rather than leaning on `supportedLocales.first` — gen-l10n sorts
/// that list, so German only leads it by alphabetical accident and a third
/// locale sorting ahead of `de` would silently move the fallback.
const kFallbackLocale = Locale('de');

/// Picks the app locale from the device's ordered language preferences,
/// matching on language code alone (we ship no region variants), and falling
/// back to [kFallbackLocale].
///
/// Used both as `MaterialApp.localeListResolutionCallback` and — outside any
/// widget tree — to localize scheduled notification copy.
Locale resolveAppLocale(List<Locale>? deviceLocales) {
  for (final device in deviceLocales ?? const <Locale>[]) {
    for (final supported in AppLocalizations.supportedLocales) {
      if (supported.languageCode == device.languageCode) return supported;
    }
  }
  return kFallbackLocale;
}
