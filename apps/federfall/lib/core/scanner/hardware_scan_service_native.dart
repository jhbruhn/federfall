import 'dart:async';
import 'dart:io';

import 'package:federfall/core/logging/app_logger.dart';
import 'package:scanwedge/scanwedge.dart';

/// Raw barcode payloads scanned by hardware scanner hardware, or a
/// permanently-dormant stream on iOS or unsupported Android devices — see
/// hardware_scan_service.dart for why this file exists.
Stream<String> hardwareScanStream() {
  if (!Platform.isAndroid) return const Stream.empty();
  final controller = StreamController<String>.broadcast();
  unawaited(_attach(controller));
  return controller.stream;
}

Future<void> _attach(StreamController<String> controller) async {
  try {
    final scanwedge = await Scanwedge.initialize();
    rootLogger.debug(
      'hardwareScanStream: initialized, '
      'isDeviceSupported=${scanwedge.isDeviceSupported}, '
      'manufacturer=${scanwedge.manufacturer}',
    );
    if (!scanwedge.isDeviceSupported) return;
    final profileCreated = await scanwedge.createScanProfile(
      ProfileModel(
        profileName: 'federfall',
        enabledBarcodes: [BarcodeConfig(barcodeType: BarcodeTypes.qrCode)],
      ),
    );
    rootLogger.debug('hardwareScanStream: profile created=$profileCreated');
    // Listened directly (not piped via controller.addStream) so a thrown
    // exception from a single malformed result can't take down delivery of
    // every later one the way an unhandled addStream error might.
    scanwedge.stream.listen(
      (result) => controller.add(result.barcode),
      onError: (Object error, StackTrace stackTrace) {
        rootLogger.debug('hardwareScanStream: scanwedge.stream error $error');
        controller.addError(error, stackTrace);
      },
      onDone: () =>
          rootLogger.debug('hardwareScanStream: scanwedge.stream done'),
    );
  } on Object catch (error, stackTrace) {
    // No compatible scanner hardware, or the plugin failed to attach — the
    // stream just stays permanently empty, same as a regular phone.
    rootLogger.debug('hardwareScanStream: attach failed: $error\n$stackTrace');
  }
}
