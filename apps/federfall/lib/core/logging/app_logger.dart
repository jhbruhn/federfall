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

/// Redacts secrets/PII from a string before it reaches a log sink.
///
/// `ClientException.toString()` (surfaced via `RepositoryException.cause`)
/// includes the full request URL — which can carry a short-lived PocketBase
/// protected-file token (`?token=...`) — and the raw JSON error response,
/// which can echo back PII the user submitted (finder name/phone/email) in
/// validation error bodies. This runs on every message/error that passes
/// through [AppLogger], including the ones that today only reach local
/// logcat/DevTools.
///
/// DO NOT wire a crash-reporting SDK (Sentry etc.) into [AppLogger] without
/// routing through this first — that would ship tokens/PII off-device
/// (OWASP A09, sensitive data exposure).
String scrubLogPayload(String text) {
  var out = text;
  // ?token=... / &token=... query params.
  out = out.replaceAllMapped(
    RegExp('([?&]token=)[^&\\s"\']+'),
    (m) => '${m[1]}***',
  );
  // Authorization: Bearer ... headers.
  out = out.replaceAllMapped(
    RegExp('(Bearer\\s+)[^\\s"\']+', caseSensitive: false),
    (m) => '${m[1]}***',
  );
  // PII field values as echoed in request/response bodies (both JSON
  // `"key":"value"` and Dart Map.toString() `key: value` shapes).
  const piiKeys = [
    'first_name',
    'last_name',
    'organisation',
    'phone',
    'alt_phone',
    'email',
    'notes',
  ];
  for (final key in piiKeys) {
    out = out.replaceAllMapped(
      RegExp('("?$key"?\\s*:\\s*)("[^"]*"|[^,}]+)'),
      (m) => '${m[1]}***',
    );
  }
  return out;
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
      scrubLogPayload(message),
      level: level.value,
      name: name ?? 'federfall',
      error: error == null ? null : scrubLogPayload(error.toString()),
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
