import 'package:federfall/l10n/federfall_strings.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:zugvogel_ui/zugvogel_ui.dart' as zv;

// The formatters now live in zugvogel_ui (eiermann-d2a.9). Two things kept
// this a wrapper rather than a re-export.
//
// The library's versions take a ZugvogelStrings for the locale, because a
// shared package may not import an l10n class (injection boundary 1), while
// every call site here passes the AppLocalizations it already holds.
//
// And formatAmountCents now requires the currency symbol: a currency is
// configuration, and a package that assumed one would be wrong for somebody.
// Federfall bills in euros, so this is where the euro sign is stated — once,
// instead of at each of its call sites.

/// Formats [value] in the active locale — `5,24` in German, `5.24` in English.
///
/// Every user-facing number goes through here so a dose never shows a dot in a
/// German UI while the keyboard next to it produces commas: mixing the two
/// separators in a clinical number is exactly how a decimal point gets
/// misread.
///
/// Grouping separators are deliberately off, and trailing zeros are dropped —
/// see the library's `formatNumber` for why.
String formatNumber(
  AppLocalizations l10n,
  double value, {
  int maxFractionDigits = 6,
}) => zv.formatNumber(
  FederfallStrings(l10n),
  value,
  maxFractionDigits: maxFractionDigits,
);

/// Formats integer [cents] as an amount in the active locale — `12,50 €` in
/// German, `€12.50` in English (intl supplies the symbol's position).
///
/// Money is stored and passed around as integer cents (`sponsorships
/// .amount_cents`) precisely so no arithmetic ever touches a binary float; this
/// is the only place it becomes a string, and [parseAmountToCents] is the only
/// place a string becomes cents again.
String formatAmountCents(AppLocalizations l10n, int cents) =>
    zv.formatAmountCents(FederfallStrings(l10n), cents, symbol: '€');

/// Integer cents from what somebody typed, or null if it is not a number.
///
/// Accepts the German decimal comma the same way every other numeric field in
/// this app does. A negative amount answers null rather than clamping to zero —
/// the field refuses it, because `-5` is a typo and storing 0 would hide it.
int? parseAmountToCents(String text) => zv.parseAmountToCents(text);
