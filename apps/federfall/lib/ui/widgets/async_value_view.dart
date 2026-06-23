import 'package:federfall/ui/widgets/error_view.dart';
import 'package:federfall/ui/widgets/loading_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Renders an [AsyncValue] with the app's standard loading and error states,
/// delegating the data case to [data].
///
/// Keeps screens free of repetitive `when(...)` boilerplate while guaranteeing
/// every async surface uses the same [LoadingView] / [ErrorView] presentation.
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

  /// Maps an error to a user-facing message; defaults to the generic title.
  final String Function(Object error)? errorMessage;

  @override
  Widget build(BuildContext context) {
    return value.when(
      skipLoadingOnReload: true,
      skipLoadingOnRefresh: true,
      data: data,
      loading: () => loading ?? const LoadingView(),
      error: (error, _) => ErrorView(
        message: errorMessage?.call(error),
        onRetry: onRetry,
      ),
    );
  }
}
