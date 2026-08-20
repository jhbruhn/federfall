// runQuickAction and confirmAndDelete now live in zugvogel_ui
// (eiermann-d2a.9). Both take only a BuildContext and their callbacks, so
// nothing about the call sites changed: the library reads its cancel label and
// its error copy off the injected ZugvogelStrings, which FederfallStrings
// answers from this app's ARB files.
//
// What they exist for is unchanged too — a form sheet shows repository errors
// inline, but a one-tap shortcut (mark done, end now, delete a tile) has no
// surface of its own, so without these a failed call was completely silent.
export 'package:zugvogel_ui/zugvogel_ui.dart'
    show confirmAndDelete, runQuickAction;
