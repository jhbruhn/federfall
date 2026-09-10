import 'package:federfall/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Bounds the width loosely. A `SizedBox` is a TIGHT constraint — every button
/// fills one, so an assertion under it proves nothing.
Widget _boxed(Widget child) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: child,
      ),
    ),
  ),
);

void main() {
  group('filled button width (federfall-78k6.9)', () {
    testWidgets('a plain FilledButton keeps its natural width', (
      tester,
    ) async {
      // The theme used to say `Size.fromHeight(48)` — Size(double.infinity,
      // 48) — so every filled button in the app was full-width. In an
      // AlertDialog's action row the confirm then took the whole bar,
      // overflowed the OverflowBar and dropped Cancel onto a line of its own.
      await tester.pumpWidget(
        _boxed(FilledButton(onPressed: () {}, child: const Text('Confirm'))),
      );
      expect(tester.getSize(find.byType(FilledButton)).width, lessThan(400));
    });

    testWidgets('the touch target stays 48 tall', (tester) async {
      await tester.pumpWidget(
        _boxed(FilledButton(onPressed: () {}, child: const Text('Confirm'))),
      );
      expect(tester.getSize(find.byType(FilledButton)).height, 48);
    });

    testWidgets('PrimaryButton still fills a form', (tester) async {
      // What the old theme default was there to buy. The button carries its
      // own width now (zugvogel 7c747d6), so the app can keep a sane default
      // and this must not regress with the pin.
      await tester.pumpWidget(
        _boxed(const PrimaryButton(label: 'Save', onPressed: null)),
      );
      expect(tester.getSize(find.byType(FilledButton)).width, 400);
    });
  });
}
