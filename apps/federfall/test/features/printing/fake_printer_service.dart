import 'dart:async';
import 'dart:typed_data';

import 'package:federfall/features/printing/printer_service.dart';

/// Records every call so widget tests can assert on printer interactions
/// without touching the real plugin (which has no web/test-VM
/// implementation) — the whole point of the [PrinterService] seam.
class FakePrinterService implements PrinterService {
  final List<PrinterDeviceRef> connected = [];
  final List<(Uint8List, ReceiptPaperSize)> receiptsPrinted = [];
  final List<(String, ReceiptPaperSize)> testTicketsPrinted = [];
  int disconnectCalls = 0;

  /// Devices to emit from [scan] the next time it's called; set before
  /// tapping "Scan" in a test.
  List<PrinterDeviceRef> scanResult = const [];
  Exception? scanError;

  Exception? connectError;
  Exception? printError;

  @override
  Stream<List<PrinterDeviceRef>> scan({
    Duration timeout = const Duration(seconds: 5),
    Set<PrinterTransport> types = allPrinterTransports,
  }) {
    if (scanError != null) return Stream.error(scanError!);
    return Stream.value(scanResult);
  }

  @override
  Future<void> connect(PrinterDeviceRef device) async {
    if (connectError != null) throw connectError!;
    connected.add(device);
  }

  @override
  Future<void> printReceipt(
    Uint8List pngBytes,
    ReceiptPaperSize paperSize,
  ) async {
    if (printError != null) throw printError!;
    receiptsPrinted.add((pngBytes, paperSize));
  }

  @override
  Future<void> printTestTicket(String text, ReceiptPaperSize paperSize) async {
    if (printError != null) throw printError!;
    testTicketsPrinted.add((text, paperSize));
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
  }

  @override
  Stream<PrinterConnState> get stateStream => const Stream.empty();

  @override
  PrinterConnState get state => PrinterConnState.disconnected;

  @override
  PrinterDeviceRef? get connectedDevice =>
      connected.isEmpty ? null : connected.last;

  @override
  void dispose() {}
}
