import 'dart:async';
import 'dart:ui';

import 'package:federfall/config/app_environment.dart';
import 'package:federfall/core/logging/app_logger.dart';
import 'package:federfall/core/logging/logging_observer.dart';
import 'package:federfall/routing/cold_start_location.dart';
import 'package:federfall/routing/last_route_storage.dart';
import 'package:federfall/routing/url_strategy/url_strategy.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// `vector_map_tiles`'s tile loader (`_VectorTileModelLoader.startLoading` in
/// `grid/tile_model.dart`) awaits its sprite-atlas fetch outside its own
/// try/catch, so disposing a tile mid-load (e.g. the find-location map
/// jumping to a picked search result) leaks a `CancellationException` as a
/// genuinely uncaught zone error instead of swallowing it like every other
/// cancellation in that function. Harmless — the tile just gets reloaded —
/// but worth filtering out here rather than logging it as a real error.
/// `executor_lib`'s `CancellationException.toString()` is the literal string
/// matched below; that package is a transitive, non-public-API dependency of
/// `vector_map_tiles`, so importing it just for an `is` check isn't worth it.
bool _isBenignVectorTileCancellation(Object error) =>
    error.toString() == 'Cancelled';

Future<void> bootstrap(FutureOr<Widget> Function() builder) async {
  WidgetsFlutterBinding.ensureInitialized();

  // One configured logger drives the global error handlers, the provider
  // observer and the in-app appLoggerProvider, so every log shares config.
  final logger = AppLogger(
    minLevel: AppEnvironment.isProduction ? LogLevel.info : LogLevel.debug,
  );
  rootLogger = logger;

  FlutterError.onError = (details) => logger.error(
    details.exceptionAsString(),
    error: details.exception,
    stackTrace: details.stack,
    name: 'flutter',
  );

  // Errors that escape the Flutter framework (platform callbacks, async gaps).
  PlatformDispatcher.instance.onError = (error, stack) {
    if (_isBenignVectorTileCancellation(error)) return true;
    logger.error('Uncaught error', error: error, stackTrace: stack);
    return true;
  };

  // Clean path-based URLs on the web (no-op on native).
  configureUrlStrategy();

  // Read before the router builds so it can use it synchronously as the
  // GoRouter's initialLocation (federfall-7ev8).
  final coldStartLocation = await LastRouteStorage().read();

  runApp(
    ProviderScope(
      observers: [LoggingProviderObserver(logger)],
      overrides: [
        appLoggerProvider.overrideWithValue(logger),
        coldStartLocationProvider.overrideWithValue(coldStartLocation),
      ],
      child: await builder(),
    ),
  );
}
