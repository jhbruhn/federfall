import 'package:federfall/l10n/gen/app_localizations.dart';
import 'package:material_ui/material_ui.dart';

export 'package:federfall/l10n/gen/app_localizations.dart';

extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// The delegates every `MaterialApp` in this app is given: its own strings
/// plus `material_ui`'s Material, Cupertino and widgets localizations.
///
/// NOT `AppLocalizations.localizationsDelegates`. gen-l10n still writes that
/// list against `flutter_localizations`, whose `MaterialLocalizations` is the
/// legacy framework type — a different class from the one `material_ui`'s
/// widgets look up. Handing it to a `material_ui` `MaterialApp` compiles, runs,
/// and quietly leaves every Material string (date pickers, "Cancel", tooltips)
/// on the English default.
const appLocalizationsDelegates = <LocalizationsDelegate<dynamic>>[
  AppLocalizations.delegate,
  ...GlobalMaterialLocalizations.delegates,
];

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
