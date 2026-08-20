// DestructiveChoice and DestructiveDialog now live in zugvogel_ui
// (eiermann-d2a.9). Every string is already a parameter — the dialog has to
// state the damage truthfully, and only the caller knows what it is — so the
// only text it read for itself was the cancel label, now injected.
export 'package:zugvogel_ui/zugvogel_ui.dart'
    show DestructiveChoice, DestructiveDialog;
