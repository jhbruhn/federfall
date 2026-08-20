import 'package:flutter/material.dart';
import 'package:zugvogel_ui/zugvogel_ui.dart';

// The two pure containers moved to zugvogel_ui (eiermann-d2a.13):
// ListDetailScaffold, which is a fixed-width pane beside a divider beside the
// rest, and DetailPanePlaceholder, whose prompt was already a parameter.
//
// ListDetailShell stayed. It is the part that has to know whether a detail is
// open, and it learns that from the route — so it depends on federfall's own
// URL shapes and on go_router's ShellRoute. A shared package cannot hold a
// widget whose behaviour is keyed on another app's route names.
export 'package:zugvogel_ui/zugvogel_ui.dart'
    show DetailPanePlaceholder, ListDetailScaffold;

/// Adaptive list-detail container shared by the cases / animals / aviaries (and
/// admin) surfaces. Wires one reusable [list] widget and the section's pane
/// navigator ([detailChild], supplied by go_router's `ShellRoute`) into the
/// right arrangement for the current width:
///
/// * **compact** → just [detailChild]; the pane navigator shows the list at the
///   section root and pushes the detail full-screen over it (native transition,
///   back gesture preserved).
/// * **expanded** → [list] on the left and [detailChild] (placeholder or the
///   selected detail) on the right. The list is rendered once, in a stable tree
///   position, so its scroll/search state survives selection changes.
///
/// Because the list is the same widget instance type in both arrangements, the
/// surfaces stay single-implementation — the panes are just containers.
///
/// Give [list] the same `GlobalKey` as the copy the section root builds on
/// compact (see the router): crossing the 840px boundary then reparents the
/// mounted list between the two positions instead of remounting it, so its
/// state also survives a rotation/resize across size classes.
class ListDetailShell extends StatelessWidget {
  const ListDetailShell({
    required this.list,
    required this.detailChild,
    super.key,
  });

  /// The reusable list widget (e.g. `CasesScreen`).
  final Widget list;

  /// The section's pane navigator from `ShellRoute` — the section root
  /// (placeholder on expanded, the list on compact) or the pushed detail.
  final Widget detailChild;

  @override
  Widget build(BuildContext context) {
    if (context.isExpanded) {
      return ListDetailScaffold(list: list, detail: detailChild);
    }
    return detailChild;
  }
}
