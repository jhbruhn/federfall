import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/core/logging/app_logger.dart';
import 'package:federfall/core/scanner/hardware_scan_service.dart';
import 'package:federfall/routing/case_deep_link_resolver.dart';
import 'package:federfall/routing/router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'hardware_scan_listener.g.dart';

/// Recognizes a `federfall://case/<caseNumber>` scan from hardware scanner
/// hardware (`hardware_scan_service.dart`) and opens that case — the same
/// deep link the case-report PDF's QR encodes, just read by dedicated
/// scanner hardware instead of a phone camera.
///
/// Started once from the app root (`ref.listen` in `app.dart`, mirroring
/// `medicationRemindersProvider`) and kept alive for the rest of the
/// session. Calling `router.go()` directly here (rather than through
/// go_router's redirect, unlike the phone-camera path in `router.dart`) is
/// safe: a hardware scan isn't also delivered to go_router automatically the
/// way a platform intent is, so there's no second handler to race against.
///
/// Extensible for whatever else scanning grows into later: recognizing
/// another kind of payload is just another branch in [_handle].
///
/// Logs each hop at debug level (dev/staging only, see `bootstrap.dart`):
/// there's no compatible scanner hardware to test against here, so this is
/// the only diagnostic trail a future hardware-specific report can lean on.
@Riverpod(keepAlive: true)
class HardwareScanListener extends _$HardwareScanListener {
  @override
  Future<void> build() async {
    final subscription = hardwareScanStream().listen(
      _handle,
      onError: _onScanError,
    );
    ref.onDispose(subscription.cancel);
  }

  void _onScanError(Object error, StackTrace stackTrace) {
    rootLogger.debug('HardwareScanListener: stream onError: $error');
    reportCaughtError(error, stackTrace);
  }

  Future<void> _handle(String data) async {
    rootLogger.debug('HardwareScanListener: received "$data"');
    final uri = Uri.tryParse(data);
    if (uri == null) return;
    try {
      final resolved = await resolveCaseDeepLink(ref, uri);
      rootLogger.debug('HardwareScanListener: resolved to $resolved');
      if (resolved != null) ref.read(routerProvider).go(resolved);
    } on Object catch (error, stackTrace) {
      rootLogger.debug('HardwareScanListener: _handle threw: $error');
      reportCaughtError(error, stackTrace);
    }
  }
}
