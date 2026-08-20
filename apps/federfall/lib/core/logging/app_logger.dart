import 'package:federfall/config/app_environment.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:zugvogel_core/zugvogel_core.dart';

// AppLogger, LogLevel, scrubLogPayload and rootLogger now live in zugvogel_core
// (eiermann-d2a.3). Read scrubLogPayload's warning there before wiring a
// crash-reporting SDK into this: it is what stops a token or a finder's phone
// number leaving the device.
//
// NOT reportCaughtError: that one keeps its single home in
// core/error/error_message.dart, which every call site already imports it from.
// Re-exporting it here too would make it ambiguous in any file that imports
// both — which is most of them.
export 'package:zugvogel_core/zugvogel_core.dart'
    show AppLogger, LogLevel, defaultPiiLogKeys, rootLogger, scrubLogPayload;

part 'app_logger.g.dart';

/// App-wide logger. Quieter in production (info+), verbose in dev (debug+).
///
/// The PROVIDER stays here, not in the package: it reads
/// [AppEnvironment.isProduction], and zugvogel holds no configuration and reads
/// no compile-time define (injection boundary 3). The channel is passed for the
/// same reason — the package cannot know this app's name, and its default is
/// the neutral 'app'.
///
/// `bootstrap` overrides this with the same instance it wires into the global
/// error handlers, so logs flow through one configured logger.
@Riverpod(keepAlive: true)
AppLogger appLogger(Ref ref) => AppLogger(
  channel: 'federfall',
  minLevel: AppEnvironment.isProduction ? LogLevel.info : LogLevel.debug,
);
