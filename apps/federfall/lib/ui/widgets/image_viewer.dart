// The full-screen image viewer now lives in zugvogel_ui (eiermann-d2a.10),
// including the `rootNavigator: true` that keeps it out of a pane-scoped
// Navigator (federfall-zbe) and the share affordance. Its labels — previous,
// next, share, and the share failure — became injected strings.
export 'package:zugvogel_ui/zugvogel_ui.dart'
    show ImageViewerScreen, showImageViewer;
