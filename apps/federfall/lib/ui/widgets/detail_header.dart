import 'package:federfall/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// Name-first identity header shared by the case detail and animal lifetime
/// screens: a dominant [title], an optional muted [subtitle] line, and an
/// optional status [chipLabel]. An optional [leading] slot holds an avatar
/// (FED-7.7 / ctw.7) to the left of the text.
///
/// Pure presentation — callers resolve the strings (a case shows its case
/// status, an animal its lifetime status), so one widget serves both without
/// knowing the domain types.
class DetailHeader extends StatelessWidget {
  const DetailHeader({
    required this.title,
    this.subtitle,
    this.chipLabel,
    this.leading,
    super.key,
  });

  /// The dominant headline (animal name, falling back to species).
  final String title;

  /// Muted secondary line (e.g. "Species · 2026-014"); omitted when null/empty.
  final String? subtitle;

  /// Status chip text; omitted when null.
  final String? chipLabel;

  /// Optional leading widget (avatar) shown left of the text.
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasSubtitle = subtitle != null && subtitle!.isNotEmpty;

    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: theme.textTheme.headlineSmall),
        if (hasSubtitle) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            subtitle!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (chipLabel != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Chip(
            label: Text(chipLabel!),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ],
    );

    if (leading == null) return text;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        leading!,
        const SizedBox(width: AppSpacing.md),
        Expanded(child: text),
      ],
    );
  }
}
