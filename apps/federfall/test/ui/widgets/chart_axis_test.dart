import 'package:federfall/ui/ui.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TitleMeta _meta({double axisPosition = 50, double parentAxisSize = 100}) =>
    TitleMeta(
      min: 0,
      max: 100,
      parentAxisSize: parentAxisSize,
      axisPosition: axisPosition,
      appliedInterval: 25,
      sideTitles: const SideTitles(showTitles: true),
      formattedValue: '50',
      axisSide: AxisSide.bottom,
      rotationQuarterTurns: 0,
    );

void main() {
  group('axisLabel', () {
    testWidgets('nudges an edge label back inside its axis by default', (
      tester,
    ) async {
      // fl_chart centres a side title on its tick, so the label at either end
      // of an axis hangs half outside the plot and is clipped there
      // (federfall-yapf).
      final label = axisLabel(_meta(axisPosition: 0), '01.01.2026');
      expect((label as SideTitleWidget).fitInside.enabled, isTrue);
    });

    testWidgets('leaves a value label on its own gridline', (tester) async {
      // The opposite call: a value label must sit exactly where its gridline
      // is, and moving the bottom one inside made a bar chart's "0" float
      // above the baseline its bars stand on.
      final label = axisLabel(_meta(axisPosition: 0), '0', fitInside: false);
      expect((label as SideTitleWidget).fitInside.enabled, isFalse);
    });

    testWidgets('keeps a label on one line', (tester) async {
      // "372.6" wrapped to a second line inside a reserved width meant for
      // three digits, which is half of what looked crooked.
      final label = axisLabel(_meta(), '1500') as SideTitleWidget;
      expect((label.child as Text).maxLines, 1);
    });
  });

  testWidgets('chartGrid draws solid horizontal hairlines only', (
    tester,
  ) async {
    late FlGridData grid;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            grid = chartGrid(context, interval: 25);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(grid.drawVerticalLine, isFalse);
    expect(grid.horizontalInterval, 25);
    // Solid, not fl_chart's dash: a dashed rule reads as a projection or a
    // threshold, which none of these charts is claiming.
    expect(grid.getDrawingHorizontalLine(0).dashArray, isNull);
  });

  group('fittingAxisLabels', () {
    Future<(String Function(int), int)> pick(
      WidgetTester tester,
      double column,
    ) async {
      late (String Function(int), int) chosen;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              chosen = fittingAxisLabels(
                context,
                column: column,
                keys: [for (var i = 1; i <= 12; i++) i],
                preferred: (i) => 'month $i',
                fallback: (i) => '$i',
                style: const TextStyle(fontSize: 10),
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      return chosen;
    }

    testWidgets('keeps the full label where every column has room', (
      tester,
    ) async {
      final (label, stride) = await pick(tester, 200);
      expect(label(3), 'month 3');
      expect(stride, 1);
    });

    testWidgets('narrows before it leaves a column unlabelled', (tester) async {
      // Skipping columns is the last resort: mapping a mark back to its
      // column is the whole job of a category axis (federfall-yapf).
      final (label, stride) = await pick(tester, 30);
      expect(label(3), '3');
      expect(stride, 1);
    });

    testWidgets('grows the stride when even the narrow form does not fit', (
      tester,
    ) async {
      final (_, stride) = await pick(tester, 3);
      expect(stride, greaterThan(1));
    });
  });

  testWidgets('labelBounds measures the widest and tallest label', (
    tester,
  ) async {
    late Size small;
    late Size large;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            small = labelBounds(context, const TextStyle(fontSize: 10), [
              '1',
              '22',
            ]);
            large = labelBounds(context, const TextStyle(fontSize: 20), [
              '1',
              '22',
            ]);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(small.width, greaterThan(0));
    // What the axis has to reserve grows with the type it is painted in —
    // which is what makes it safe at the reader's own text scale.
    expect(large.width, greaterThan(small.width));
    expect(large.height, greaterThan(small.height));
  });
}
