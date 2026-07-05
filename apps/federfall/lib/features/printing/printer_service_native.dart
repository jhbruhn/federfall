import 'dart:async';
import 'dart:typed_data';

import 'package:federfall/features/printing/printer_service.dart';
import 'package:image/image.dart' as img;
import 'package:unified_esc_pos_printer/unified_esc_pos_printer.dart'
    as printer;

/// Real implementation (federfall-i0wq), selected by printer_service.dart's
/// conditional import whenever `dart:io` is available (i.e. never on web —
/// see that file's doc comment). This is the ONLY file in the app that
/// imports `package:unified_esc_pos_printer` or `package:image`; every other
/// printer-adjacent file works with the plain types in printer_service.dart.
PrinterService createPrinterService() => _PrinterManagerService();

class _PrinterManagerService implements PrinterService {
  final printer.PrinterManager _manager = printer.PrinterManager();

  @override
  Stream<List<PrinterDeviceRef>> scan({
    Duration timeout = const Duration(seconds: 5),
    Set<PrinterTransport> types = allPrinterTransports,
  }) => _manager
      .scanAll(timeout: timeout, types: types.map(_toPackageType).toSet())
      .map((devices) => devices.map(_toDeviceRef).toList());

  @override
  Future<void> connect(PrinterDeviceRef device) =>
      _manager.connect(_toPackageDevice(device));

  /// Blank line fed before the cut — without it the cut lands mid-content on
  /// printers with an auto-cutter offset (verified against the Epson
  /// TM-T88IV). No leading feed: `Ticket.feed()`'s own default (1 line)
  /// already covers the top — the tear-off edge gives the masthead enough
  /// breathing room on its own, unlike the last line, which needs real
  /// clearance before the blade.
  static const _bottomMarginLines = 3;

  @override
  Future<void> printReceipt(
    Uint8List pngBytes,
    ReceiptPaperSize paperSize,
  ) async {
    final receiptImage = img.decodePng(pngBytes);
    if (receiptImage == null) {
      throw const FormatException('Could not decode receipt PNG.');
    }
    final ticket = await printer.Ticket.create(_toPackagePaperSize(paperSize))
      ..feed()
      ..imageRaster(receiptImage)
      ..feed(_bottomMarginLines)
      ..cut();
    await _manager.printTicket(ticket);
  }

  @override
  Future<void> printTestTicket(String text, ReceiptPaperSize paperSize) async {
    final ticket = await printer.Ticket.create(_toPackagePaperSize(paperSize))
      ..feed()
      ..text(
        text,
        align: printer.PrintAlign.center,
        style: const printer.PrintTextStyle(bold: true),
      )
      ..feed(_bottomMarginLines)
      ..cut();
    await _manager.printTicket(ticket);
  }

  @override
  Future<void> disconnect() => _manager.disconnect();

  @override
  Stream<PrinterConnState> get stateStream =>
      _manager.stateStream.map(_toConnState);

  @override
  PrinterConnState get state => _toConnState(_manager.state);

  @override
  PrinterDeviceRef? get connectedDevice {
    final device = _manager.connectedDevice;
    return device == null ? null : _toDeviceRef(device);
  }

  @override
  void dispose() => _manager.dispose();

  printer.PrinterConnectionType _toPackageType(PrinterTransport t) =>
      switch (t) {
        PrinterTransport.network => printer.PrinterConnectionType.network,
        PrinterTransport.ble => printer.PrinterConnectionType.ble,
        PrinterTransport.bluetooth => printer.PrinterConnectionType.bluetooth,
        PrinterTransport.usb => printer.PrinterConnectionType.usb,
      };

  printer.PaperSize _toPackagePaperSize(ReceiptPaperSize s) => switch (s) {
    ReceiptPaperSize.mm58 => printer.PaperSize.mm58,
    ReceiptPaperSize.mm72 => printer.PaperSize.mm72,
    ReceiptPaperSize.mm80 => printer.PaperSize.mm80,
  };

  PrinterConnState _toConnState(printer.PrinterConnectionState s) =>
      switch (s) {
        printer.PrinterConnectionState.disconnected =>
          PrinterConnState.disconnected,
        printer.PrinterConnectionState.scanning => PrinterConnState.scanning,
        printer.PrinterConnectionState.connecting =>
          PrinterConnState.connecting,
        printer.PrinterConnectionState.connected => PrinterConnState.connected,
        printer.PrinterConnectionState.printing => PrinterConnState.printing,
        printer.PrinterConnectionState.disconnecting =>
          PrinterConnState.disconnecting,
        printer.PrinterConnectionState.error => PrinterConnState.error,
      };

  PrinterDeviceRef _toDeviceRef(printer.PrinterDevice device) =>
      switch (device) {
        printer.NetworkPrinterDevice() => NetworkPrinterDeviceRef(
          name: device.name,
          host: device.host,
          port: device.port,
        ),
        printer.BlePrinterDevice() => BlePrinterDeviceRef(
          name: device.name,
          deviceId: device.deviceId,
          serviceUuid: device.serviceUuid,
          txCharacteristicUuid: device.txCharacteristicUuid,
        ),
        printer.BluetoothPrinterDevice() => BluetoothPrinterDeviceRef(
          name: device.name,
          address: device.address,
        ),
        printer.UsbPrinterDevice() => UsbPrinterDeviceRef(
          name: device.name,
          identifier: device.identifier,
          usbPlatform: switch (device.usbPlatform) {
            printer.UsbPlatform.android => UsbDevicePlatform.android,
            printer.UsbPlatform.desktop => UsbDevicePlatform.desktop,
          },
        ),
        _ => throw StateError(
          'Unknown PrinterDevice subtype: ${device.runtimeType}',
        ),
      };

  printer.PrinterDevice _toPackageDevice(PrinterDeviceRef ref) => switch (ref) {
    NetworkPrinterDeviceRef() => printer.NetworkPrinterDevice(
      name: ref.name,
      host: ref.host,
      port: ref.port,
    ),
    BlePrinterDeviceRef() => printer.BlePrinterDevice(
      name: ref.name,
      deviceId: ref.deviceId,
      serviceUuid: ref.serviceUuid,
      txCharacteristicUuid: ref.txCharacteristicUuid,
    ),
    BluetoothPrinterDeviceRef() => printer.BluetoothPrinterDevice(
      name: ref.name,
      address: ref.address,
    ),
    UsbPrinterDeviceRef() => printer.UsbPrinterDevice(
      name: ref.name,
      identifier: ref.identifier,
      usbPlatform: switch (ref.usbPlatform) {
        UsbDevicePlatform.android => printer.UsbPlatform.android,
        UsbDevicePlatform.desktop => printer.UsbPlatform.desktop,
      },
    ),
  };
}
