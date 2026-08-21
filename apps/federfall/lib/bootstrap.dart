import 'dart:async';
import 'dart:ui';

import 'package:federfall/config/app_environment.dart';
import 'package:federfall/config/zugvogel_bindings.dart';
import 'package:federfall/core/logging/app_logger.dart';
import 'package:federfall/l10n/federfall_strings.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/routing/url_strategy/url_strategy.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:zugvogel_pb_client/zugvogel_pb_client.dart'
    show LoggingProviderObserver;
import 'package:zugvogel_ui/zugvogel_ui.dart';

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

  // `intl`'s date symbols, which `DateFormat` needs before it will accept a
  // locale. Inside the widget tree flutter_localizations' delegate loads them
  // as a side effect, but the reminder planner formats appointment times with
  // no BuildContext and runs from a provider the root widget merely `listen`s —
  // i.e. possibly before that delegate. Without this, a cold start could throw
  // ArgumentError('Invalid locale "de"') out of the planner and schedule
  // nothing at all, medication reminders included. (Synchronous work behind an
  // already-completed Future, so the await costs a microtask.)
  await initializeDateFormatting();

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

  // What zugvogel needs to know about this app: the service name that derives
  // the /api/federfall/info route, the identity marker and the storage keys,
  // plus the map fallback and the flavor-dependent http allowance. The library
  // reads no compile-time define of its own (injection boundary 3), so this is
  // the one place those cross over. Set before the ProviderScope below, so no
  // provider can be read without it.
  defaultPbClientConfig = federfallPbClientConfig();

  // Where the shared widgets get their words. It takes the BuildContext rather
  // than a ready-made instance so the strings stay locale-reactive: reading
  // this app's localizations out of the context on every build is what
  // registers the dependency a locale change needs, where a cached instance
  // would freeze the language at startup.
  defaultZugvogelStrings = (context) => FederfallStrings(context.l10n);

  runApp(
    ProviderScope(
      observers: [LoggingProviderObserver(logger)],
      overrides: [appLoggerProvider.overrideWithValue(logger)],
      child: await builder(),
    ),
  );
}
