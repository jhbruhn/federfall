import 'package:federfall/l10n/federfall_strings.dart';
import 'package:federfall/l10n/gen/app_localizations.dart';
import 'package:zugvogel_ui/zugvogel_ui.dart' as zv;

// The validators themselves now live in zugvogel_ui (eiermann-d2a.9). What
// stayed is the shape of the call: the library's factories take a
// ZugvogelStrings, because a shared package may not import an l10n class
// (injection boundary 1), while ~100 call sites in this app pass the
// AppLocalizations they already have in hand.
//
// So this is a wrapper rather than a re-export. Adapting the l10n costs one
// small object per validator and keeps the seam invisible at the call site,
// which is the point: nothing about validating a form field was worth touching
// a hundred screens for.

/// Reusable, localized form-field validators.
///
/// Each factory takes the [AppLocalizations] so messages stay translated, and
/// returns a `String? Function(String?)` matching `FormField.validator`.
abstract final class Validators {
  /// Fails when the trimmed value is empty.
  static String? Function(String?) required(AppLocalizations l10n) =>
      zv.Validators.required(FederfallStrings(l10n));

  /// Fails when the value is not a syntactically valid http(s) URL. Empty
  /// passes — compose with [required] when the field is mandatory.
  static String? Function(String?) url(AppLocalizations l10n) =>
      zv.Validators.url(FederfallStrings(l10n));

  /// Fails when the value is not a plausible email address. Empty passes.
  static String? Function(String?) email(AppLocalizations l10n) =>
      zv.Validators.email(FederfallStrings(l10n));

  /// Fails when the value is shorter than [min] characters. Empty passes —
  /// compose with [required] when the field is mandatory. The value is not
  /// trimmed (passwords may legitimately start or end with whitespace).
  static String? Function(String?) minLength(AppLocalizations l10n, int min) =>
      zv.Validators.minLength(FederfallStrings(l10n), min);

  /// Fails when the value is not an integer of at least [min]. Empty passes —
  /// compose with [required] when the field is mandatory.
  static String? Function(String?) intMin(AppLocalizations l10n, int min) =>
      zv.Validators.intMin(FederfallStrings(l10n), min);

  /// Runs [validators] in order, returning the first failure.
  static String? Function(String?) compose(
    List<String? Function(String?)> validators,
  ) => zv.Validators.compose(validators);
}
