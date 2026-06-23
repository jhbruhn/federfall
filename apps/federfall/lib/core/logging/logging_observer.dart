import 'package:federfall/core/logging/app_logger.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Logs every provider failure through [AppLogger], giving app-wide visibility
/// into async errors (failed loads, thrown notifiers) without each provider
/// having to log for itself.
final class LoggingProviderObserver extends ProviderObserver {
  const LoggingProviderObserver(this._logger);

  final AppLogger _logger;

  @override
  void providerDidFail(
    ProviderObserverContext context,
    Object error,
    StackTrace stackTrace,
  ) {
    final name = context.provider.name ?? context.provider.runtimeType;
    _logger.error(
      'Provider failed: $name',
      error: error,
      stackTrace: stackTrace,
      name: 'riverpod',
    );
  }
}
