// AsyncValueView now lives in zugvogel_ui (eiermann-d2a.9), including the rule
// that matters most in it: loaded data stays on screen when the refresh fails
// with a network error, because the offline strip already states the
// connection — while a permission or validation error still replaces it.
export 'package:zugvogel_ui/zugvogel_ui.dart' show AsyncValueView;
