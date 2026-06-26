import 'package:federfall/ui/layout/content_bounds.dart';
import 'package:federfall/ui/layout/window_size.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpAt(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    const Directionality(
      textDirection: TextDirection.ltr,
      child: ContentBounds(
        child: SizedBox(width: double.infinity, height: 10),
      ),
    ),
  );
}

void main() {
  testWidgets('caps content width on a wide window', (tester) async {
    await _pumpAt(tester, const Size(1600, 800));

    final box = tester.widget<ConstrainedBox>(find.byType(ConstrainedBox));
    expect(box.constraints.maxWidth, kContentMaxWidth);
    // The child is capped (centred), not stretched to the full window width.
    expect(tester.getSize(find.byType(SizedBox)).width, kContentMaxWidth);
  });

  testWidgets('fills the available width below the cap', (tester) async {
    await _pumpAt(tester, const Size(400, 800));

    expect(tester.getSize(find.byType(SizedBox)).width, 400);
  });
}
