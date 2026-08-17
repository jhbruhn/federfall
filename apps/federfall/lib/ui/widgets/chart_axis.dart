import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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

/// Air either side of a label on a category axis, so two never touch.
const double _labelGap = 4;

/// The locale's narrow month name for a month number — "J" for January.
///
/// Five Ms is intl's narrow form, i.e. the locale's own letter rather than a
/// substring the app slices out of the abbreviation itself. It is the fallback
/// a month axis reaches for before it starts leaving columns unlabelled: one
/// letter is thin, but in calendar order it is still read as months.
String Function(int) narrowMonthLabel(BuildContext context) {
  final narrow = DateFormat(
    'MMMMM',
    Localizations.localeOf(context).toString(),
  );
  return (month) => narrow.format(DateTime(2000, month));
}

/// Which spelling of a category label fits the width one column gets, and how
/// many columns to skip between labels.
///
/// [preferred] is used for every column where it fits. Where it does not,
/// [fallback] — a narrower spelling of the same thing, e.g. a month's single
/// letter instead of its abbreviation — is tried before any column is left
/// unlabelled: reading a category axis means mapping a mark back to its
/// column, and a label every nth turns that into a counting exercise. Only
/// when the narrow form does not fit either does the stride grow.
///
/// [keys] are the values both forms are asked about — the same keys the axis
/// labels — and [column] is what one of them gets in pixels.
(String Function(int), int) fittingAxisLabels(
  BuildContext context, {
  required double column,
  required Iterable<int> keys,
  required String Function(int) preferred,
  required String Function(int) fallback,
  TextStyle? style,
}) {
  final all = keys.toList();
  int strideFor(String Function(int) form) {
    if (column <= 0 || all.isEmpty) return 1;
    final widest = labelBounds(context, style, all.map(form)).width;
    return ((widest + _labelGap) / column).ceil().clamp(1, all.length);
  }

  if (strideFor(preferred) == 1) return (preferred, 1);
  return (fallback, strideFor(fallback));
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
