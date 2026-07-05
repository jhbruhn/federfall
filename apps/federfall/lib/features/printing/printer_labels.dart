import 'package:federfall/features/printing/printer_service.dart';
import 'package:federfall/l10n/gen/app_localizations.dart';

/// Localized display labels for printer connectivity (federfall-i0wq),
/// mirroring `cases_labels.dart`'s pattern for the case code lists.
String paperSizeLabel(AppLocalizations l10n, ReceiptPaperSize size) =>
    switch (size) {
      ReceiptPaperSize.mm58 => l10n.printerPaperSizeMm58,
      ReceiptPaperSize.mm72 => l10n.printerPaperSizeMm72,
      ReceiptPaperSize.mm80 => l10n.printerPaperSizeMm80,
    };

String printerTransportLabel(AppLocalizations l10n, PrinterTransport type) =>
    switch (type) {
      PrinterTransport.network => l10n.printerConnectionTypeNetwork,
      PrinterTransport.ble => l10n.printerConnectionTypeBle,
      PrinterTransport.bluetooth => l10n.printerConnectionTypeBluetooth,
      PrinterTransport.usb => l10n.printerConnectionTypeUsb,
    };

/// One line describing a saved/discovered device beyond its bare `name` —
/// shown as a subtitle wherever [PrinterDeviceRef.name] alone (often a MAC
/// address or "localhost") wouldn't tell the user which transport it is.
String printerDeviceDetail(AppLocalizations l10n, PrinterDeviceRef device) {
  final transport = printerTransportLabel(l10n, device.transport);
  return switch (device) {
    NetworkPrinterDeviceRef() => '$transport · ${device.host}:${device.port}',
    BluetoothPrinterDeviceRef() => '$transport · ${device.address}',
    BlePrinterDeviceRef() => '$transport · ${device.deviceId}',
    UsbPrinterDeviceRef() => '$transport · ${device.identifier}',
  };
}
