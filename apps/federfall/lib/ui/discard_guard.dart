// confirmDiscardChanges and the DiscardGuard mixin now live in zugvogel_ui
// (eiermann-d2a.9). Only the wording was federfall's, and it no longer travels
// with the code: the dialog reads its four strings off the injected
// ZugvogelStrings, which FederfallStrings answers from this app's ARB files.
export 'package:zugvogel_ui/zugvogel_ui.dart'
    show DiscardGuard, confirmDiscardChanges;
