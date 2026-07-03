import 'package:federfall/ui/ui.dart';
import 'package:flutter/material.dart';

/// One row in the case chronology. Every event kind — milestones and journal
/// entries alike — renders through this so they share a single visual language:
/// a leading rail (an icon dot joined by a connecting line) and a content
/// column headed by the event's [date], with optional [trailing] actions.
class TimelineItem extends StatelessWidget {
  const TimelineItem({
    required this.icon,
    required this.date,
    required this.child,
    this.trailing,
    this.isLast = false,
    super.key,
  });

  /// Glyph shown in the rail dot (distinguishes the event kind).
  final IconData icon;

  /// Formatted date/time header; empty hides the header text.
  final String date;

  /// The event body (a label, or a note with photos).
  final Widget child;

  /// Optional actions aligned with the date header (e.g. an overflow menu).
  final Widget? trailing;

  /// When true the connecting line below the dot is omitted (last event).
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateText = Text(
      date,
      style: theme.textTheme.labelMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
    // The header strip stays a compact 32dp — a 48px action box in the header
    // row would inflate it and push the body down, making editable entries sit
    // lower than read-only ones (federfall-533). Instead the action keeps its
    // full 48dp accessible tap target by overlaying the header strip and the
    // body's top-right corner (federfall-neym).
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (trailing == null)
          dateText
        else
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: _dotSize),
            padding: const EdgeInsets.only(right: _actionTargetSize),
            alignment: Alignment.centerLeft,
            child: dateText,
          ),
        const SizedBox(height: AppSpacing.xs),
        child,
      ],
    );
    // The connecting line is painted behind the row rather than stretched
    // alongside it — stretching would need IntrinsicHeight (a second layout
    // pass per row), which is too costly for a chronology with hundreds of
    // entries.
    return Stack(
      children: [
        if (!isLast)
          Positioned(
            left: _dotSize / 2 - 1,
            top: _dotSize,
            bottom: 0,
            width: 2,
            child: ColoredBox(color: theme.colorScheme.outlineVariant),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Dot(icon: icon),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpacing.lg),
                child: switch (trailing) {
                  null => content,
                  final t => Stack(
                    children: [
                      content,
                      Positioned(
                        top: 0,
                        right: 0,
                        child: SizedBox.square(
                          dimension: _actionTargetSize,
                          child: t,
                        ),
                      ),
                    ],
                  ),
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The overflow menu on a timeline tile's trailing action: an edit item,
/// optional [leadingItems]/[middleItems] for entry-specific actions (e.g. a
/// "log dose" or "mark done"), and an optional delete item — [onDelete] is
/// null (and thus omitted) when the current user isn't allowed to delete.
class TimelineEntryMenu extends StatelessWidget {
  const TimelineEntryMenu({
    required this.editLabel,
    required this.onEdit,
    this.tooltip,
    this.deleteLabel,
    this.onDelete,
    this.leadingItems = const [],
    this.middleItems = const [],
    super.key,
  });

  final String editLabel;
  final VoidCallback onEdit;

  /// Defaults to [editLabel] when omitted.
  final String? tooltip;
  final String? deleteLabel;
  final VoidCallback? onDelete;

  /// Items shown before the edit item (e.g. a primary "log dose" action).
  final List<PopupMenuEntry<void>> leadingItems;

  /// Items shown between the edit and delete items.
  final List<PopupMenuEntry<void>> middleItems;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<void>(
      icon: const Icon(Icons.more_vert),
      iconSize: 20,
      padding: EdgeInsets.zero,
      tooltip: tooltip ?? editLabel,
      itemBuilder: (context) => [
        ...leadingItems,
        PopupMenuItem(onTap: onEdit, child: Text(editLabel)),
        ...middleItems,
        if (onDelete != null)
          PopupMenuItem(onTap: onDelete, child: Text(deleteLabel!)),
      ],
    );
  }
}

/// Minimum accessible tap target (Material) for the trailing action.
const double _actionTargetSize = 48;

const double _dotSize = 32;

/// The rail's circular icon dot; the connecting line down to the next event
/// is painted separately behind the row (see [TimelineItem.build]).
class _Dot extends StatelessWidget {
  const _Dot({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: _dotSize,
      height: _dotSize,
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        shape: BoxShape.circle,
      ),
      child: Icon(
        icon,
        size: 18,
        color: theme.colorScheme.onSecondaryContainer,
      ),
    );
  }
}
