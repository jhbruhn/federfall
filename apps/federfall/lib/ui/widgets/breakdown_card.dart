// ChartEntry, BreakdownRow and BreakdownCard now live in zugvogel_ui
// (eiermann-d2a.12). The card was already structural — a title, an optional
// chart, counted rows — and the entries carry only a label and a number, which
// is what keeps the charts independent of where the numbers came from.
export 'package:zugvogel_ui/zugvogel_ui.dart'
    show BreakdownCard, BreakdownRow, ChartEntry;
