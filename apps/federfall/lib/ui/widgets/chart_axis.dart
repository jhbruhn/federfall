// The chart axis helpers now live in zugvogel_ui (eiermann-d2a.12): an axis
// label, the grid, the narrow month names a cramped axis needs, the text
// measurement that reserves room for them, and the search that thins labels
// until they fit the width actually available.
export 'package:zugvogel_ui/zugvogel_ui.dart'
    show axisLabel, chartGrid, fittingAxisLabels, labelBounds, narrowMonthLabel;
