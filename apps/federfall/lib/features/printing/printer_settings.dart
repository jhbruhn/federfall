import 'package:federfall/features/printing/printer_service.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'printer_settings.g.dart';

/// The persisted printer choice (federfall-i0wq): which physical printer to
/// use, if any, and the paper width its raster is sized for. Deliberately
/// ONE value rather than two independently-set ones — [paperSize] feeds BOTH
/// the `?widthDots=` sent to `PbCaseReportRepository.fetchReceiptPng` and the
/// print-time raster width (see `PrinterService.printReceipt`'s doc), and
/// the library can't auto-detect a connected printer's dot width, so a wrong
/// choice here silently misprints on real hardware.
class PrinterSettings {
  const PrinterSettings({
    this.device,
    this.paperSize = ReceiptPaperSize.mm72,
  });

  /// `null` means no printer has been configured yet.
  final PrinterDeviceRef? device;

  /// Defaults to 72mm/512px — the Epson TM-T88IV, this feature's primary
  /// verified-first target (see federfall-i0wq epic notes).
  final ReceiptPaperSize paperSize;
}

/// Persists [PrinterSettings] in `shared_preferences`, mirroring
/// `reminder_settings.dart`'s pattern. [PrinterDeviceRef] is a small closed
/// hierarchy (network/BLE/Bluetooth/USB), so it's stored as flat fields
/// under one key per field rather than JSON — reading back only consults the
/// fields for the stored `_keyType`, so stale fields from a previously
/// configured transport are harmless leftovers, not a migration concern.
@Riverpod(keepAlive: true)
class PrinterSettingsNotifier extends _$PrinterSettingsNotifier {
  static const _keyType = 'printer_device_type';
  static const _keyName = 'printer_device_name';
  static const _keyHost = 'printer_device_host';
  static const _keyPort = 'printer_device_port';
  static const _keyBleDeviceId = 'printer_device_ble_device_id';
  static const _keyBleServiceUuid = 'printer_device_ble_service_uuid';
  static const _keyBleTxCharacteristicUuid =
      'printer_device_ble_tx_characteristic_uuid';
  static const _keyBluetoothAddress = 'printer_device_bluetooth_address';
  static const _keyUsbIdentifier = 'printer_device_usb_identifier';
  static const _keyUsbPlatform = 'printer_device_usb_platform';
  static const _keyPaperSize = 'printer_paper_size';

  @override
  Future<PrinterSettings> build() async {
    final prefs = await SharedPreferences.getInstance();
    return PrinterSettings(
      device: _deviceFromPrefs(prefs),
      paperSize: _paperSizeFromWire(prefs.getString(_keyPaperSize)),
    );
  }

  /// Save [device] as the configured printer, keeping the current paper size.
  Future<void> setDevice(PrinterDeviceRef device) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyName, device.name);
    switch (device) {
      case NetworkPrinterDeviceRef():
        await prefs.setString(_keyType, 'network');
        await prefs.setString(_keyHost, device.host);
        await prefs.setInt(_keyPort, device.port);
      case BlePrinterDeviceRef():
        await prefs.setString(_keyType, 'ble');
        await prefs.setString(_keyBleDeviceId, device.deviceId);
        await _setOrRemove(prefs, _keyBleServiceUuid, device.serviceUuid);
        await _setOrRemove(
          prefs,
          _keyBleTxCharacteristicUuid,
          device.txCharacteristicUuid,
        );
      case BluetoothPrinterDeviceRef():
        await prefs.setString(_keyType, 'bluetooth');
        await prefs.setString(_keyBluetoothAddress, device.address);
      case UsbPrinterDeviceRef():
        await prefs.setString(_keyType, 'usb');
        await prefs.setString(_keyUsbIdentifier, device.identifier);
        await prefs.setString(_keyUsbPlatform, device.usbPlatform.name);
    }
    state = AsyncData(
      PrinterSettings(device: device, paperSize: _currentPaperSize()),
    );
  }

  /// Forget the configured printer (paper size is kept — it's a property of
  /// the paper the user loads, independent of which printer is selected).
  Future<void> clearDevice() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyType);
    state = AsyncData(PrinterSettings(paperSize: _currentPaperSize()));
  }

  Future<void> setPaperSize(ReceiptPaperSize paperSize) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPaperSize, paperSize.name);
    state = AsyncData(
      PrinterSettings(device: state.value?.device, paperSize: paperSize),
    );
  }

  ReceiptPaperSize _currentPaperSize() =>
      state.value?.paperSize ?? ReceiptPaperSize.mm72;

  Future<void> _setOrRemove(
    SharedPreferences prefs,
    String key,
    String? value,
  ) => value == null ? prefs.remove(key) : prefs.setString(key, value);

  PrinterDeviceRef? _deviceFromPrefs(SharedPreferences prefs) {
    final name = prefs.getString(_keyName);
    if (name == null) return null;
    switch (prefs.getString(_keyType)) {
      case 'network':
        final host = prefs.getString(_keyHost);
        if (host == null) return null;
        return NetworkPrinterDeviceRef(
          name: name,
          host: host,
          port: prefs.getInt(_keyPort) ?? 9100,
        );
      case 'ble':
        final deviceId = prefs.getString(_keyBleDeviceId);
        if (deviceId == null) return null;
        return BlePrinterDeviceRef(
          name: name,
          deviceId: deviceId,
          serviceUuid: prefs.getString(_keyBleServiceUuid),
          txCharacteristicUuid: prefs.getString(_keyBleTxCharacteristicUuid),
        );
      case 'bluetooth':
        final address = prefs.getString(_keyBluetoothAddress);
        if (address == null) return null;
        return BluetoothPrinterDeviceRef(name: name, address: address);
      case 'usb':
        final identifier = prefs.getString(_keyUsbIdentifier);
        final usbPlatformWire = prefs.getString(_keyUsbPlatform);
        if (identifier == null || usbPlatformWire == null) return null;
        return UsbPrinterDeviceRef(
          name: name,
          identifier: identifier,
          usbPlatform: UsbDevicePlatform.values.byName(usbPlatformWire),
        );
      default:
        return null;
    }
  }

  ReceiptPaperSize _paperSizeFromWire(String? wire) {
    for (final size in ReceiptPaperSize.values) {
      if (size.name == wire) return size;
    }
    return ReceiptPaperSize.mm72;
  }
}
