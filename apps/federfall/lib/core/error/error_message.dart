import 'package:federfall/l10n/gen/app_localizations.dart';
import 'package:federfall_data/federfall_data.dart';

/// Maps an arbitrary error into user-facing, localized copy.
///
/// [RepositoryException]s are translated by their [RepositoryErrorKind]; any
/// other error falls back to a generic message. Use this to feed
/// `AsyncValueView.errorMessage` or snackbars so the UI never shows raw
/// exception strings.
String errorMessage(AppLocalizations l10n, Object error) {
  if (error is RepositoryException) {
    return switch (error.kind) {
      RepositoryErrorKind.network => l10n.errorOffline,
      RepositoryErrorKind.unauthorized => l10n.errorUnauthorized,
      RepositoryErrorKind.notFound => l10n.errorNotFound,
      RepositoryErrorKind.validation => l10n.errorValidation,
      RepositoryErrorKind.unknown => l10n.errorGenericTitle,
    };
  }
  return l10n.errorGenericTitle;
}
