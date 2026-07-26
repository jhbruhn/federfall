import 'package:federfall/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// One entry in a popup menu: an icon, a label, and what it does.
///
/// Every entry carries an icon. A menu where some rows have one and some do not
/// reads as two lists that happen to share a popup, and the icon is what makes
/// a row recognizable before it is read.
@immutable
class MenuAction {
  const MenuAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;

  /// Runs after the menu closes (Material's own `PopupMenuItem.onTap` timing),
  /// so an action may open a dialog or sheet of its own.
  final VoidCallback onTap;

  /// Marks an irreversible entry — a delete.
  ///
  /// Rendered in the error colour *and* separated from the safe entries above
  /// it by a divider, so the colour is never the only thing distinguishing the
  /// dangerous row (WCAG 2.1 SC 1.4.1). This is the menu counterpart of the
  /// rule `DestructiveActionButton` applies in dialogs, where shape and weight
  /// carry the warning and the colour only reinforces it.
  final bool destructive;
}

/// Renders [actions] as popup-menu entries, splitting the destructive tail off
/// from the safe entries above it with a divider.
///
/// A menu whose only entry is destructive gets no divider — there is nothing to
/// separate it from, and a rule above a lone row reads as a missing item.
List<PopupMenuEntry<void>> buildMenuItems(List<MenuAction> actions) {
  final items = <PopupMenuEntry<void>>[];
  for (final (i, action) in actions.indexed) {
    if (action.destructive && i > 0 && !actions[i - 1].destructive) {
      items.add(const PopupMenuDivider());
    }
    items.add(
      PopupMenuItem<void>(onTap: action.onTap, child: _MenuRow(action)),
    );
  }
  return items;
}

/// The row inside one menu entry: icon, gap, label.
class _MenuRow extends StatelessWidget {
  const _MenuRow(this.action);

  final MenuAction action;

  @override
  Widget build(BuildContext context) {
    final color = action.destructive
        ? Theme.of(context).colorScheme.error
        : null;
    return Row(
      children: [
        Icon(action.icon, color: color),
        const SizedBox(width: AppSpacing.md),
        // Wraps rather than truncating: a menu is as wide as its longest label
        // only up to the popup's own limit, past which a German compound would
        // otherwise lose its ending.
        Expanded(
          child: Text(
            action.label,
            style: color == null ? null : TextStyle(color: color),
          ),
        ),
      ],
    );
  }
}
