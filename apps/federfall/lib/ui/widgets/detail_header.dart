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
    this.footer,
    this.chipLabel,
    this.leading,
    this.trailing,
    super.key,
  });

  /// The dominant headline (animal name, falling back to species).
  final String title;

  /// Muted secondary line (e.g. "Species · 2026-014"); omitted when null/empty.
  final String? subtitle;

  /// Optional extra line under the subtitle, aligned with the text column (e.g.
  /// the active carer). Sits above the status chip; omitted when null.
  final Widget? footer;

  /// Status chip text; omitted when null.
  final String? chipLabel;

  /// Optional leading widget (avatar) shown left of the text.
  final Widget? leading;

  /// Optional trailing widget (e.g. a read-only badge), aligned top-end.
  final Widget? trailing;

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
        if (footer != null) ...[
          const SizedBox(height: AppSpacing.xs),
          footer!,
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

    // Fill the width and align left so a shrink-wrapped header is never
    // centred by a parent Column's default cross-axis alignment.
    if (leading == null && trailing == null) {
      return Align(alignment: AlignmentDirectional.centerStart, child: text);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (leading != null) ...[
          leading!,
          const SizedBox(width: AppSpacing.md),
        ],
        Expanded(child: text),
        if (trailing != null) ...[
          const SizedBox(width: AppSpacing.sm),
          trailing!,
        ],
      ],
    );
  }
}
