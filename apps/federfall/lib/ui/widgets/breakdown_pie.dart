// BreakdownPie now lives in zugvogel_ui (eiermann-d2a.12) — including the rule
// that a pie is an all-pairs form, so the tail past three hues folds into one
// neutral slice instead of growing new colours.
//
// The hues themselves had to become injected: they were six hex literals here,
// and a shared package may not name a colour (injection boundary 2). They now
// come from the categorical palette on ZugvogelSemantics, which `AppTheme`
// registers per brightness — still two palettes each validated against its own
// surface, never one flipped for the other.
export 'package:zugvogel_ui/zugvogel_ui.dart' show BreakdownPie;
