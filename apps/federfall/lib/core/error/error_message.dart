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
}) =>
    rootLogger.error(
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
