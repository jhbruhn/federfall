import 'dart:async';
import 'dart:typed_data';

import 'package:federfall/features/printing/printer_service_stub.dart'
    if (dart.library.io) 'package:federfall/features/printing/printer_service_native.dart'
    as platform;
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'printer_service.g.dart';

/// Every printer-adjacent type below is a plain, package-agnostic
/// description — NOT a re-export of `package:unified_esc_pos_printer`'s own
/// types (federfall-i0wq). That package's core classes (`PrinterManager`,
/// `NetworkConnector`, `BluetoothConnector`) unconditionally `import
/// 'dart:io'`, with no web-safe fallback (its own `dart.library.html`
/// conditional-import guard in usb_connector.dart doesn't help either — it
/// doesn't detect Flutter's newer `--wasm` web target, since `dart:html`
/// isn't available there either, so the check silently picks the wrong,
/// dart:io-importing branch). Importing that package from ANY file reachable
/// by the web build — even just for a type like PaperSize — breaks web
/// compilation outright, regardless of `!kIsWeb` runtime guards, since
/// Dart's front end must resolve the whole import graph before it can even
/// consider what's reachable at runtime.
///
/// So the actual package only gets imported from
/// printer_service_native.dart, which THIS file conditionally imports via
/// `if (dart.library.io)` — `dart:io` is reliably absent on every web
/// target (dart2js and dart2wasm alike) and present on every platform this
/// app ships natively (Android/iOS/desktop), unlike `dart:html`. Every other
/// file in this feature (settings, labels, the config sheet, the profile
/// section, the case-detail print button) depends only on the plain types
/// below, never on the underlying package.
enum ReceiptPaperSize {
  mm58(widthPixels: 384),
  mm72(widthPixels: 512),
  mm80(widthPixels: 576);

  const ReceiptPaperSize({required this.widthPixels});

  /// Matches `PaperSize.widthPixels` 1:1 — this is the value sent as
  /// `?widthDots=` to `PbCaseReportRepository.fetchReceiptPng` AND (via the
  /// native implementation) the physical raster width printed, so the two
  /// can never drift apart.
  final int widthPixels;
}

enum PrinterTransport { network, ble, bluetooth, usb }

enum PrinterConnState {
  disconnected,
  scanning,
  connecting,
  connected,
  printing,
  disconnecting,
  error,
}

/// A discovered or previously-saved printer. Concrete subtypes carry
/// transport-specific fields, mirroring `unified_esc_pos_printer`'s own
/// `PrinterDevice` hierarchy one-to-one (translated in
/// printer_service_native.dart) — kept separate so this file itself stays
/// web-safe.
sealed class PrinterDeviceRef {
  const PrinterDeviceRef({required this.name});

  final String name;

  PrinterTransport get transport;
}

class NetworkPrinterDeviceRef extends PrinterDeviceRef {
  const NetworkPrinterDeviceRef({
    required super.name,
    required this.host,
    this.port = 9100,
  });

  final String host;
  final int port;

  @override
  PrinterTransport get transport => PrinterTransport.network;
}

class BlePrinterDeviceRef extends PrinterDeviceRef {
  const BlePrinterDeviceRef({
    required super.name,
    required this.deviceId,
    this.serviceUuid,
    this.txCharacteristicUuid,
  });

  final String deviceId;
  final String? serviceUuid;
  final String? txCharacteristicUuid;

  @override
  PrinterTransport get transport => PrinterTransport.ble;
}

class BluetoothPrinterDeviceRef extends PrinterDeviceRef {
  const BluetoothPrinterDeviceRef({required super.name, required this.address});

  final String address;

  @override
  PrinterTransport get transport => PrinterTransport.bluetooth;
}

enum UsbDevicePlatform { android, desktop }

class UsbPrinterDeviceRef extends PrinterDeviceRef {
  const UsbPrinterDeviceRef({
    required super.name,
    required this.identifier,
    required this.usbPlatform,
  });

  final String identifier;
  final UsbDevicePlatform usbPlatform;

  @override
  PrinterTransport get transport => PrinterTransport.usb;
}

/// The four transports a scan can search — kept here so callers don't need
/// to reach into the native implementation just to pass the default set.
const Set<PrinterTransport> allPrinterTransports = {
  PrinterTransport.network,
  PrinterTransport.ble,
  PrinterTransport.bluetooth,
  PrinterTransport.usb,
};

/// What the printer-settings and print-action screens need: scan / connect /
/// print / disconnect / connection state. The real implementation
/// (printer_service_native.dart) wraps `PrinterManager`; tests supply a
/// mocktail fake instead.
abstract class PrinterService {
  Stream<List<PrinterDeviceRef>> scan({
    Duration timeout = const Duration(seconds: 5),
    Set<PrinterTransport> types = allPrinterTransports,
  });

  Future<void> connect(PrinterDeviceRef device);

  /// Prints [pngBytes] (an already-rasterized receipt, exactly
  /// [paperSize].widthPixels wide — see `case_report.pb.js`'s `widthDots`)
  /// on the connected printer, followed by a paper cut.
  Future<void> printReceipt(Uint8List pngBytes, ReceiptPaperSize paperSize);

  /// Sends a short test ticket (plain [text], centered, bold) to the
  /// connected printer, followed by a paper cut.
  Future<void> printTestTicket(String text, ReceiptPaperSize paperSize);

  Future<void> disconnect();

  Stream<PrinterConnState> get stateStream;

  PrinterConnState get state;

  PrinterDeviceRef? get connectedDevice;

  /// Release all resources. Call when the owning provider is disposed.
  void dispose();
}

/// `unified_esc_pos_printer` has no web support at all (epic federfall-i0wq)
/// — every screen that surfaces printing must ALSO guard its UI with
/// `if (!kIsWeb)` (see profile_screen.dart), but picking the no-op here too
/// means a stray `ref.watch` on web fails safe instead of touching a plugin
/// with no web implementation.
class NoopPrinterService implements PrinterService {
  @override
  Stream<List<PrinterDeviceRef>> scan({
    Duration timeout = const Duration(seconds: 5),
    Set<PrinterTransport> types = allPrinterTransports,
  }) => const Stream.empty();

  @override
  Future<void> connect(PrinterDeviceRef device) async {}

  @override
  Future<void> printReceipt(Uint8List pngBytes, ReceiptPaperSize size) async {}

  @override
  Future<void> printTestTicket(String text, ReceiptPaperSize size) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Stream<PrinterConnState> get stateStream => const Stream.empty();

  @override
  PrinterConnState get state => PrinterConnState.disconnected;

  @override
  PrinterDeviceRef? get connectedDevice => null;

  @override
  void dispose() {}
}

/// One [PrinterService] for the app's lifetime — printer connections are
/// stateful (a physical link, not a request/response call) and should
/// survive navigating away from and back to the settings/print screens.
/// `platform.createPrinterService()` resolves to the stub (always Noop) on
/// web and the real `PrinterManager`-backed implementation everywhere else
/// — picked by the conditional import above, not a runtime check.
@Riverpod(keepAlive: true)
PrinterService printerService(Ref ref) {
  final service = platform.createPrinterService();
  ref.onDispose(service.dispose);
  return service;
}
