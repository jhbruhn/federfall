import 'dart:developer' as developer;

import 'package:federfall/config/app_environment.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_logger.g.dart';

/// Severity levels; values mirror `dart:developer` log levels so they show up
/// sensibly in DevTools and IDE logs.
enum LogLevel {
  debug(500),
  info(800),
  warning(900),
  error(1000);

  const LogLevel(this.value);

  /// Numeric level passed to `dart:developer`.
  final int value;
}

/// The app's logging facade.
///
/// Thin wrapper over `dart:developer` so call sites stay simple and a single
/// [minLevel] gate keeps production logs quiet. Error reporting (Sentry etc.)
/// can later hook in here without touching call sites.
class AppLogger {
  const AppLogger({this.minLevel = LogLevel.debug});

  /// Messages below this level are dropped.
  final LogLevel minLevel;

  void debug(String message, {String? name}) =>
      _log(LogLevel.debug, message, name: name);

  void info(String message, {String? name}) =>
      _log(LogLevel.info, message, name: name);

  void warning(String message, {Object? error, String? name}) =>
      _log(LogLevel.warning, message, error: error, name: name);

  void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    String? name,
  }) =>
      _log(
        LogLevel.error,
        message,
        error: error,
        stackTrace: stackTrace,
        name: name,
      );

  void _log(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    String? name,
  }) {
    if (level.value < minLevel.value) return;
    developer.log(
      message,
      level: level.value,
      name: name ?? 'federfall',
      error: error,
      stackTrace: stackTrace,
    );
  }
}

/// App-wide logger. Quieter in production (info+), verbose in dev (debug+).
///
/// `bootstrap` overrides this with the same instance it wires into the global
/// error handlers, so logs flow through one configured logger.
@Riverpod(keepAlive: true)
AppLogger appLogger(Ref ref) => AppLogger(
      minLevel: AppEnvironment.isProduction ? LogLevel.info : LogLevel.debug,
    );

/// The logger `bootstrap` configured, for call sites without a `Ref` (e.g.
/// `reportCaughtError`). Set once by `bootstrap` to the same instance behind
/// [appLoggerProvider], so a crash-reporting hook wired in there also sees
/// errors reported outside the provider graph. Defaults to a plain logger for
/// tests and tools that never run `bootstrap`.
AppLogger rootLogger = const AppLogger();
