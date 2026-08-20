import 'package:federfall/l10n/gen/app_localizations.dart';
import 'package:zugvogel_ui/zugvogel_ui.dart';

// The shared widgets moved to zugvogel_ui (eiermann-d2a.9), and none of them
// may import an l10n class: a widget that knows the word "Abbrechen" welds one
// product's voice into code two products share (injection boundary 1). So the
// text arrives through this interface instead, and this file is the single
// place where federfall's ARB files answer for it.
//
// Every member delegates. There is deliberately no wording of its own here —
// if a string were written in this file it would be a translation nobody could
// find from the ARB files, and `flutter gen-l10n` would never see it.

/// Federfall's voice for the shared widgets.
///
/// Built per `BuildContext` (see `defaultZugvogelStrings` in `bootstrap`) so a
/// locale change re-reads the app's own localizations rather than replaying a
/// language frozen at startup.
class FederfallStrings implements ZugvogelStrings {
  const FederfallStrings(this._l10n);

  final AppLocalizations _l10n;

  @override
  String get localeName => _l10n.localeName;

  @override
  String get actionCancel => _l10n.actionCancel;

  @override
  String get actionRetry => _l10n.actionRetry;

  @override
  String get actionSave => _l10n.actionSave;

  @override
  String get discardChangesTitle => _l10n.discardChangesTitle;

  @override
  String get discardChangesMessage => _l10n.discardChangesMessage;

  @override
  String get discardConfirm => _l10n.discardConfirm;

  @override
  String get discardKeepEditing => _l10n.discardKeepEditing;

  @override
  String get loadingLabel => _l10n.loadingLabel;

  @override
  String get emptyGeneric => _l10n.emptyGeneric;

  @override
  String get offlineNotice => _l10n.offlineNotice;

  @override
  String get errorGenericTitle => _l10n.errorGenericTitle;

  @override
  String get errorOffline => _l10n.errorOffline;

  @override
  String get errorUnauthorized => _l10n.errorUnauthorized;

  @override
  String get errorNotFound => _l10n.errorNotFound;

  @override
  String get errorValidation => _l10n.errorValidation;

  @override
  String get errorUnknownOutcome => _l10n.errorUnknownOutcome;

  @override
  String get errorLoadFailed => _l10n.errorLoadFailed;

  @override
  String get fieldRequired => _l10n.fieldRequired;

  @override
  String get fieldInvalidEmail => _l10n.fieldInvalidEmail;

  @override
  String get fieldInvalidUrl => _l10n.fieldInvalidUrl;

  @override
  String fieldMinLength(int min) => _l10n.fieldMinLength(min);

  @override
  String fieldIntMin(int min) => _l10n.fieldIntMin(min);

  @override
  String get photoAddAction => _l10n.photoAddAction;

  @override
  String get photoCaptureAction => _l10n.photoCaptureAction;

  @override
  String get imageCropTitle => _l10n.imageCropTitle;

  @override
  String get imageCropFailed => _l10n.imageCropFailed;

  @override
  String get imagePrevious => _l10n.imagePrevious;

  @override
  String get imageNext => _l10n.imageNext;

  @override
  String get imageShareAction => _l10n.imageShareAction;

  @override
  String get imageShareFailed => _l10n.imageShareFailed;
}
