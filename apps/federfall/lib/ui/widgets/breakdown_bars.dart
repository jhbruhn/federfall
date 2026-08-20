// BreakdownBars now lives in zugvogel_ui (eiermann-d2a.12).
//
// The one thing that had to become injected is the fill colour. It used to be
// two hex literals picked here, one per brightness; a shared package may not
// name a colour (injection boundary 2), so the bar now takes the first entry of
// the categorical palette on ZugvogelSemantics. `AppTheme` registers
// federfall's own palette in both themes with exactly the former hues, so a
// bar still looks the way it did.
export 'package:zugvogel_ui/zugvogel_ui.dart' show BreakdownBars;
