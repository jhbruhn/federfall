import 'package:federfall/theme/app_spacing.dart';
import 'package:federfall/ui/layout/window_size.dart';
import 'package:federfall/ui/widgets/empty_view.dart';
import 'package:flutter/material.dart';

/// Pure two-pane layout: a fixed-width [list] on the left, a divider, and the
/// [detail] filling the rest. Knows nothing about routing — callers decide what
/// each pane is and when to use it (see [ListDetailShell]).
class ListDetailScaffold extends StatelessWidget {
  const ListDetailScaffold({
    required this.list,
    required this.detail,
    super.key,
  });

  /// Left pane — the list. Constrained to [kListPaneWidth].
  final Widget list;

  /// Right pane — the selected item's detail (or a [DetailPanePlaceholder]).
  final Widget detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: kListPaneWidth, child: list),
        const VerticalDivider(width: 1),
        Expanded(child: detail),
      ],
    );
  }
}

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

/// The empty right pane shown on expanded widths before anything is selected.
class DetailPanePlaceholder extends StatelessWidget {
  const DetailPanePlaceholder({required this.message, this.icon, super.key});

  /// Prompt, e.g. "Select a case to view its details".
  final String message;

  /// Optional leading icon; defaults to a neutral selection cue.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    // A Material of its own so the pane has a proper background (and text/icon
    // theming) even when it renders outside a Scaffold — e.g. as the right pane
    // of the management hub, which is a bare Row.
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: EmptyView(
          icon: icon ?? Icons.touch_app_outlined,
          message: message,
        ),
      ),
    );
  }
}
