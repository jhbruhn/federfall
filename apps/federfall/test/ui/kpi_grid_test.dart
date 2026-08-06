import 'package:federfall/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<double> _tileWidth(WidgetTester tester, double available) async {
  // The surface has to be wider than the box under test, or the Scaffold
  // clamps it and the grid sizes to the window instead of to its constraints.
  tester.view.physicalSize = Size(available + 200, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: available,
          child: KpiGrid([
            for (var i = 0; i < 5; i++)
              KpiCard(icon: Icons.pets, label: 'L$i', value: '$i'),
          ]),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tester.getSize(find.byType(KpiCard).first).width;
}

void main() {
  testWidgets('a phone keeps two columns', (tester) async {
    final width = await _tileWidth(tester, 360);
    expect(width, closeTo((360 - 16) / 2, 1));
  });

  testWidgets('a wide window earns more columns, up to four', (tester) async {
    // Five tiles in two columns is three rows of scrolling on a desktop.
    expect(await _tileWidth(tester, 800), lessThan(300));
    expect(await _tileWidth(tester, 1200), closeTo((1200 - 48) / 4, 1));
    // ...and never a fifth: past four the eye stops reading a row.
    expect(await _tileWidth(tester, 2000), closeTo((2000 - 48) / 4, 1));
  });
}
