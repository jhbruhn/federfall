import 'package:federfall/l10n/federfall_strings.dart';
import 'package:federfall/l10n/gen/app_localizations.dart';
import 'package:zugvogel_ui/zugvogel_ui.dart' as zv;

// The mapping from RepositoryErrorKind to user-facing copy moved to
// zugvogel_ui (eiermann-d2a.9). Sharing the mapping while injecting the
// wording is the whole point of it: it is what stops one app quietly rendering
// "not reached, try again" over a write whose outcome is genuinely unknown,
// where a blind retry can duplicate data.
//
// errorMessage and loadErrorMessage stay wrappers because the library's take a
// ZugvogelStrings — a shared package may not import an l10n class (injection
// boundary 1) — while every one of the ~90 call sites here holds an
// AppLocalizations already.
//
// reportCaughtError is now zugvogel_core's, re-exported from its long-standing
// home here so no call site changes. It still routes through rootLogger, which
// `bootstrap` points at the one configured logger.
export 'package:zugvogel_core/zugvogel_core.dart' show reportCaughtError;
export 'package:zugvogel_ui/zugvogel_ui.dart' show isNetworkError;

/// Maps an arbitrary error into user-facing, localized copy.
///
/// A `RepositoryException` is translated by its `RepositoryErrorKind`; any
/// other error falls back to a generic message. Use this to feed
/// `AsyncValueView.errorMessage` or snackbars so the UI never shows raw
/// exception strings.
String errorMessage(AppLocalizations l10n, Object error) =>
    zv.errorMessage(FederfallStrings(l10n), error);

/// Like [errorMessage], but phrased for a surface that failed to *load*.
///
/// [errorMessage]'s network copy promises "your entry is kept", which only
/// makes sense for a write — a failed read has no entry to keep. The offline
/// strip already accounts for the connection, so this reports the one thing the
/// strip cannot know: that this particular content is missing.
String loadErrorMessage(AppLocalizations l10n, Object error) =>
    zv.loadErrorMessage(FederfallStrings(l10n), error);
