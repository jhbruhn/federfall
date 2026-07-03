import 'package:federfall/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// A small rounded tag chip, e.g. for a condition's certainty or a
/// medication's controlled-substance badge. Defaults to the theme's
/// secondary container colors when [color]/[onColor] are omitted.
class TagChip extends StatelessWidget {
  const TagChip({required this.label, this.color, this.onColor, super.key});

  final String label;
  final Color? color;
  final Color? onColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = color ?? theme.colorScheme.secondaryContainer;
    final fg = onColor ?? theme.colorScheme.onSecondaryContainer;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(color: fg),
      ),
    );
  }
}
