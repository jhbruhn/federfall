import 'package:federfall/ui/ui.dart';
import 'package:flutter/material.dart';

/// One metric tile: a tonal [IconChip], the number as the hero, and a receding
/// label. When [onTap] is set a chevron marks the tile as a way in to the
/// records behind the number.
///
/// Shared by the dashboard's caseload grid and the statistics screen
/// (federfall-p2xa) — the same object should not be drawn two ways.
class KpiCard extends StatelessWidget {
  const KpiCard({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;

  /// Pre-formatted, so a tile can show a plain count, a localized duration or
  /// an em dash for "not enough data".
  final String value;

  /// Omit for a tile that only reports. The chevron follows this, so a tile
  /// never promises a destination it does not have.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon seated in a soft tonal square: gives the grid a colour
              // rhythm and echoes the empty-state disc language.
              IconChip(icon),
              const SizedBox(height: AppSpacing.md),
              // The metric is the hero: large, semibold, tabular figures so
              // stacked tiles align digit-for-digit and don't reflow.
              Text(
                value,
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  height: 1,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              // The label recedes; the chevron moves down beside it so the top
              // row is a single confident icon, not a tug-of-war.
              Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (onTap != null)
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: colors.onSurfaceVariant,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lays [tiles] out as a two-column grid of equal-width [KpiCard]s.
///
/// The width comes from the incoming constraints rather than a fixed number, so
/// tiles grow with the pane and a long label at a large text scale gets room to
/// wrap instead of overflowing.
class KpiGrid extends StatelessWidget {
  const KpiGrid(this.tiles, {super.key});

  final List<KpiCard> tiles;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - AppSpacing.md) / 2;
        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            for (final tile in tiles) SizedBox(width: width, child: tile),
          ],
        );
      },
    );
  }
}
