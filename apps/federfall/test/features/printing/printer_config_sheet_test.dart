import 'package:federfall/features/printing/printer_config_sheet.dart';
import 'package:federfall/features/printing/printer_service.dart';
import 'package:federfall/features/printing/printer_settings.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_printer_service.dart';

Future<FakePrinterService> _open(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final fake = FakePrinterService();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [printerServiceProvider.overrideWithValue(fake)],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showPrinterConfigSheet(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return fake;
}

void main() {
  testWidgets('scanning shows discovered devices and selecting saves one', (
    tester,
  ) async {
    final fake = await _open(tester);
    fake.scanResult = const [
      NetworkPrinterDeviceRef(name: 'Epson TM-T88IV', host: '10.0.0.5'),
    ];

    await tester.tap(find.widgetWithText(TextButton, 'Scan'));
    await tester.pumpAndSettle();

    expect(find.text('Epson TM-T88IV'), findsOneWidget);
    expect(find.textContaining('10.0.0.5:9100'), findsOneWidget);

    await tester.tap(find.text('Epson TM-T88IV'));
    await tester.pumpAndSettle();

    // The sheet closes itself on a successful save (Navigator.pop).
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Configure printer'), findsNothing);
  });

  testWidgets('an empty scan shows the empty-state message', (tester) async {
    await _open(tester);

    await tester.tap(find.widgetWithText(TextButton, 'Scan'));
    await tester.pumpAndSettle();

    expect(find.text('No printers found yet.'), findsOneWidget);
  });

  testWidgets('adding a network printer manually requires host and port', (
    tester,
  ) async {
    await _open(tester);

    // Blank host: validation blocks the add, sheet stays open.
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Port'),
      '9100',
    );
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(find.text('Configure printer'), findsOneWidget);
  });

  testWidgets('adding a valid network printer saves it and closes', (
    tester,
  ) async {
    await _open(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Host or IP address'),
      '192.168.1.20',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Port'),
      '9100',
    );
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(find.text('Configure printer'), findsNothing);
  });

  testWidgets('changing the paper size persists the selection', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final fake = FakePrinterService();
    final container = ProviderContainer(
      overrides: [printerServiceProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showPrinterConfigSheet(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('72 mm (512 px)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('58 mm (384 px)').last);
    await tester.pumpAndSettle();

    final settings = await container.read(printerSettingsProvider.future);
    expect(settings.paperSize, ReceiptPaperSize.mm58);
  });
}
