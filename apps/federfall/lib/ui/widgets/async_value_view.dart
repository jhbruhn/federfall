import 'package:federfall/core/error/error_message.dart' as core_error;
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/widgets/error_view.dart';
import 'package:federfall/ui/widgets/loading_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Renders an [AsyncValue] with the app's standard loading and error states,
/// delegating the data case to [data].
///
/// Keeps screens free of repetitive `when(...)` boilerplate while guaranteeing
/// every async surface uses the same [LoadingView] / [ErrorView] presentation.
/// Errors are already logged app-wide by `LoggingProviderObserver`, so this
/// widget only renders them.
class AsyncValueView<T> extends StatelessWidget {
  const AsyncValueView({
    required this.value,
    required this.data,
    this.onRetry,
    this.loading,
    this.errorMessage,
    super.key,
  });

  /// The async state to render.
  final AsyncValue<T> value;

  /// Builds the UI for the loaded value.
  final Widget Function(T data) data;

  /// Invoked by the error state's retry button (typically `ref.invalidate`).
  final VoidCallback? onRetry;

  /// Optional custom loading widget; defaults to [LoadingView].
  final Widget? loading;

  /// Maps an error to a user-facing message; defaults to the app-wide
  /// localized mapping (`loadErrorMessage` in `core/error/error_message.dart`).
  final String Function(Object error)? errorMessage;

  @override
  Widget build(BuildContext context) {
    // A dropped connection must not wipe out data that is already on screen.
    // `OfflineNotice` states the cause app-wide, so replacing a populated list
    // with a full-screen error would only cost the user their scroll position
    // and filters — for a condition they can do nothing about but wait out.
    // Every other failure still surfaces: quietly serving stale data after a
    // permission or validation error would be dishonest.
    if (value.hasValue &&
        value.hasError &&
        core_error.isNetworkError(value.error!)) {
      return data(value.requireValue);
    }
    return value.when(
      skipLoadingOnReload: true,
      skipLoadingOnRefresh: true,
      data: data,
      loading: () => loading ?? const LoadingView(),
      error: (error, _) => ErrorView(
        message:
            errorMessage?.call(error) ??
            core_error.loadErrorMessage(context.l10n, error),
        onRetry: onRetry,
      ),
    );
  }
}
