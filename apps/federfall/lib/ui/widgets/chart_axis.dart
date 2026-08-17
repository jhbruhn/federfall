import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// Axis furniture shared by the app's charts, so the three of them are read
/// the same way.
///
/// fl_chart centres whatever `getTitlesWidget` returns on its tick and lets it
/// hang over either end of the axis, so a plain `Text` at the edge of a chart
/// is half-clipped: the weight trend's first date sat under the value axis and
/// its last one was cut off mid-word. [axisLabel] wraps the text in fl_chart's
/// own [SideTitleWidget] with `fitInside`, which nudges exactly those two back
/// inside the plot and leaves every label between them where it was
/// (federfall-yapf).
Widget axisLabel(
  TitleMeta meta,
  String text, {
  TextStyle? style,
  bool fitInside = true,
}) => SideTitleWidget(
  meta: meta,
  fitInside: fitInside
      ? SideTitleFitInsideData.fromTitleMeta(meta)
      : SideTitleFitInsideData.disable(),
  child: Text(text, style: style, maxLines: 1),
);

/// A recessive grid: solid hairlines one shade off the surface, horizontal
/// only, one line per [interval] (null lets fl_chart choose).
///
/// Solid rather than fl_chart's dashed default — a dashed rule reads as a
/// projection or a threshold, which is a claim none of these charts is making.
FlGridData chartGrid(BuildContext context, {double? interval}) {
  final color = Theme.of(context).colorScheme.outlineVariant;
  return FlGridData(
    drawVerticalLine: false,
    horizontalInterval: interval,
    getDrawingHorizontalLine: (_) => FlLine(color: color, strokeWidth: 1),
  );
}

/// The box the widest and tallest of [labels] needs as this theme paints them
/// — including the reader's text scale, which is what decides whether an axis
/// label wraps onto a second line or is cut off.
Size labelBounds(
  BuildContext context,
  TextStyle? style,
  Iterable<String> labels,
) {
  final painter = TextPainter(
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  );
  var widest = 0.0;
  var tallest = 0.0;
  for (final label in labels) {
    painter
      ..text = TextSpan(text: label, style: style)
      ..layout();
    if (painter.width > widest) widest = painter.width;
    if (painter.height > tallest) tallest = painter.height;
  }
  painter.dispose();
  return Size(widest, tallest);
}
