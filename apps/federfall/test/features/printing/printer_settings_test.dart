import 'package:federfall/features/printing/printer_service.dart';
import 'package:federfall/features/printing/printer_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

ProviderContainer _container() {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('defaults to no device and 72mm when nothing is persisted', () async {
    SharedPreferences.setMockInitialValues({});
    final container = _container();

    final settings = await container.read(printerSettingsProvider.future);

    expect(settings.device, isNull);
    expect(settings.paperSize, ReceiptPaperSize.mm72);
  });

  test('setDevice persists and reads back a network device', () async {
    SharedPreferences.setMockInitialValues({});
    final container = _container();
    await container.read(printerSettingsProvider.future);

    await container
        .read(printerSettingsProvider.notifier)
        .setDevice(
          const NetworkPrinterDeviceRef(
            name: '192.168.1.50',
            host: '192.168.1.50',
          ),
        );

    final settings = container.read(printerSettingsProvider).value!;
    final device = settings.device! as NetworkPrinterDeviceRef;
    expect(device.host, '192.168.1.50');
    expect(device.port, 9100);

    // A second notifier reading the SAME persisted prefs (a fresh app start)
    // must reconstruct the identical device — this is the actual behaviour
    // that matters, not just the in-memory state right after setDevice.
    final container2 = _container();
    final reloaded = await container2.read(printerSettingsProvider.future);
    final reloadedDevice = reloaded.device! as NetworkPrinterDeviceRef;
    expect(reloadedDevice.host, '192.168.1.50');
    expect(reloadedDevice.port, 9100);
  });

  test('setDevice persists and reads back a BLE device', () async {
    SharedPreferences.setMockInitialValues({});
    final container = _container();
    await container.read(printerSettingsProvider.future);

    await container
        .read(printerSettingsProvider.notifier)
        .setDevice(
          const BlePrinterDeviceRef(
            name: 'BLE Printer',
            deviceId: 'AA:BB:CC',
            serviceUuid: 'svc-1',
            txCharacteristicUuid: 'tx-1',
          ),
        );

    final container2 = _container();
    final reloaded = await container2.read(printerSettingsProvider.future);
    final device = reloaded.device! as BlePrinterDeviceRef;
    expect(device.deviceId, 'AA:BB:CC');
    expect(device.serviceUuid, 'svc-1');
    expect(device.txCharacteristicUuid, 'tx-1');
  });

  test(
    'setDevice persists and reads back a Bluetooth Classic device',
    () async {
      SharedPreferences.setMockInitialValues({});
      final container = _container();
      await container.read(printerSettingsProvider.future);

      await container
          .read(printerSettingsProvider.notifier)
          .setDevice(
            const BluetoothPrinterDeviceRef(
              name: 'BT Printer',
              address: '00:11:22:33:44:55',
            ),
          );

      final container2 = _container();
      final reloaded = await container2.read(printerSettingsProvider.future);
      final device = reloaded.device! as BluetoothPrinterDeviceRef;
      expect(device.address, '00:11:22:33:44:55');
    },
  );

  test('setDevice persists and reads back a USB device', () async {
    SharedPreferences.setMockInitialValues({});
    final container = _container();
    await container.read(printerSettingsProvider.future);

    await container
        .read(printerSettingsProvider.notifier)
        .setDevice(
          const UsbPrinterDeviceRef(
            name: 'USB Printer',
            identifier: '1234:5678',
            usbPlatform: UsbDevicePlatform.android,
          ),
        );

    final container2 = _container();
    final reloaded = await container2.read(printerSettingsProvider.future);
    final device = reloaded.device! as UsbPrinterDeviceRef;
    expect(device.identifier, '1234:5678');
    expect(device.usbPlatform, UsbDevicePlatform.android);
  });

  test('setPaperSize persists across a fresh read', () async {
    SharedPreferences.setMockInitialValues({});
    final container = _container();
    await container.read(printerSettingsProvider.future);

    await container
        .read(printerSettingsProvider.notifier)
        .setPaperSize(ReceiptPaperSize.mm58);

    final container2 = _container();
    final reloaded = await container2.read(printerSettingsProvider.future);
    expect(reloaded.paperSize, ReceiptPaperSize.mm58);
  });

  test('clearDevice forgets the device but keeps the paper size', () async {
    SharedPreferences.setMockInitialValues({});
    final container = _container();
    await container.read(printerSettingsProvider.future);
    final notifier = container.read(printerSettingsProvider.notifier);
    await notifier.setPaperSize(ReceiptPaperSize.mm80);
    await notifier.setDevice(
      const NetworkPrinterDeviceRef(name: 'x', host: 'x'),
    );

    await notifier.clearDevice();

    final settings = container.read(printerSettingsProvider).value!;
    expect(settings.device, isNull);
    expect(settings.paperSize, ReceiptPaperSize.mm80);

    final container2 = _container();
    final reloaded = await container2.read(printerSettingsProvider.future);
    expect(reloaded.device, isNull);
    expect(reloaded.paperSize, ReceiptPaperSize.mm80);
  });
}
