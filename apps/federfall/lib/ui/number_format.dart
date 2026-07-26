import 'package:federfall/l10n/l10n.dart';
import 'package:intl/intl.dart';

/// Formats [value] in the active locale — `5,24` in German, `5.24` in English.
///
/// Every user-facing number goes through here so a dose never shows a dot in a
/// German UI while the keyboard next to it produces commas: mixing the two
/// separators in a clinical number is exactly how a decimal point gets
/// misread.
///
/// Grouping separators are deliberately off. These numbers are round-tripped
/// through the app's own number fields, whose parser only knows to turn a
/// comma into a dot, so a grouped `1.234,5` would come back as nonsense.
/// Trailing zeros are dropped, so a whole number reads `248`, not `248.0`.
String formatNumber(
  AppLocalizations l10n,
  double value, {
  int maxFractionDigits = 6,
}) {
  final format = NumberFormat.decimalPattern(l10n.localeName)
    ..turnOffGrouping()
    ..maximumFractionDigits = maxFractionDigits;
  return format.format(value);
}
