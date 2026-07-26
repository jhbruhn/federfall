import 'package:federfall/core/logging/app_logger.dart';
import 'package:federfall/l10n/gen/app_localizations.dart';
import 'package:federfall_data/federfall_data.dart';

/// Reports an error swallowed by a broad `on Object` handler.
///
/// Such handlers deliberately show the user only a generic message (see
/// [errorMessage]); this keeps the underlying error observable for debugging
/// and crash reporting by routing it through [AppLogger] — the same funnel
/// `bootstrap` wires the global error handlers into. Logging (rather than
/// `FlutterError.reportError`) is used on purpose: widget tests treat reported
/// framework errors as failures, but a swallowed error is expected behaviour.
void reportCaughtError(
  Object error,
  StackTrace stackTrace, {
  String? context,
}) => rootLogger.error(
  context ?? 'Unexpected error (shown to the user as a generic message)',
  error: error,
  stackTrace: stackTrace,
);

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
      RepositoryErrorKind.unknownOutcome => l10n.errorUnknownOutcome,
      RepositoryErrorKind.unknown => l10n.errorGenericTitle,
    };
  }
  return l10n.errorGenericTitle;
}

/// Whether [error] means the app could not reach its server.
///
/// Lets a caller defer to the app-wide offline strip (`OfflineNotice`) instead
/// of restating the connection in its own words — see `AsyncValueView`, which
/// uses it to keep loaded data on screen through a dropped connection.
bool isNetworkError(Object error) =>
    error is RepositoryException && error.kind == RepositoryErrorKind.network;

/// Like [errorMessage], but phrased for a surface that failed to *load*.
///
/// [errorMessage]'s network copy promises "your entry is kept", which only
/// makes sense for a write — a failed read has no entry to keep. The offline
/// strip already accounts for the connection, so this reports the one thing the
/// strip cannot know: that this particular content is missing.
String loadErrorMessage(AppLocalizations l10n, Object error) =>
    isNetworkError(error) ? l10n.errorLoadFailed : errorMessage(l10n, error);
