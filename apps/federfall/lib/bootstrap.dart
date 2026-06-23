import 'dart:async';
import 'dart:ui';

import 'package:federfall/config/app_environment.dart';
import 'package:federfall/core/logging/app_logger.dart';
import 'package:federfall/core/logging/logging_observer.dart';
import 'package:federfall/routing/url_strategy/url_strategy.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> bootstrap(FutureOr<Widget> Function() builder) async {
  WidgetsFlutterBinding.ensureInitialized();

  // One configured logger drives the global error handlers, the provider
  // observer and the in-app appLoggerProvider, so every log shares config.
  final logger = AppLogger(
    minLevel: AppEnvironment.isProduction ? LogLevel.info : LogLevel.debug,
  );

  FlutterError.onError = (details) => logger.error(
        details.exceptionAsString(),
        error: details.exception,
        stackTrace: details.stack,
        name: 'flutter',
      );

  // Errors that escape the Flutter framework (platform callbacks, async gaps).
  PlatformDispatcher.instance.onError = (error, stack) {
    logger.error('Uncaught error', error: error, stackTrace: stack);
    return true;
  };

  // Clean path-based URLs on the web (no-op on native).
  configureUrlStrategy();

  runApp(
    ProviderScope(
      observers: [LoggingProviderObserver(logger)],
      overrides: [appLoggerProvider.overrideWithValue(logger)],
      child: await builder(),
    ),
  );
}
