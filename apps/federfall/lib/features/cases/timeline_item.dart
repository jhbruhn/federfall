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
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Rail(icon: icon, isLast: isLast),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          date,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      // Pin the action to a compact square. Menus/buttons
                      // otherwise impose a 48px tap target that inflates the
                      // date header and pushes the body down — making editable
                      // entries sit lower than read-only ones (federfall-533).
                      if (trailing case final t?)
                        SizedBox.square(dimension: 32, child: t),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  child,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The leading rail: a circular icon dot with a vertical line running down to
/// the next event (trimmed on the last one).
class _Rail extends StatelessWidget {
  const _Rail({required this.icon, required this.isLast});

  final IconData icon;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 32,
      child: Column(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 18,
              color: theme.colorScheme.onSecondaryContainer,
            ),
          ),
          if (!isLast)
            Expanded(
              child: Container(
                width: 2,
                color: theme.colorScheme.outlineVariant,
              ),
            ),
        ],
      ),
    );
  }
}
