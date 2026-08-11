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

/// Formats integer [cents] as an amount in the active locale — `12,50 €` in
/// German, `€12.50` in English (intl supplies the symbol's position).
///
/// Money is stored and passed around as integer cents (`sponsorships
/// .amount_cents`) precisely so no arithmetic ever touches a binary float; this
/// is the only place it becomes a string, and [parseAmountToCents] is the only
/// place a string becomes cents again.
///
/// Always two fraction digits, unlike [formatNumber]: „12 €" and „12,00 €" are
/// the same amount, but a donation figure read against a bank statement should
/// look like a donation figure.
String formatAmountCents(AppLocalizations l10n, int cents) {
  final format = NumberFormat.currency(
    locale: l10n.localeName,
    symbol: '€',
    decimalDigits: 2,
  );
  return format.format(cents / 100);
}

/// Integer cents from what somebody typed, or null if it is not a number.
///
/// Accepts the German decimal comma the same way every other numeric field in
/// this app does (`double.tryParse` after swapping in a dot). The double lives
/// only inside this function: it is rounded to cents before it leaves, so no
/// caller can accumulate float error.
///
/// A negative amount answers null rather than clamping to zero — the field
/// refuses it, because `-5` is a typo and storing 0 would hide it.
int? parseAmountToCents(String text) {
  final euros = double.tryParse(text.trim().replaceAll(',', '.'));
  if (euros == null || euros.isNaN || euros.isInfinite || euros < 0) {
    return null;
  }
  return (euros * 100).round();
}
