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
    this.note,
    this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;

  /// Pre-formatted, so a tile can show a plain count, a localized duration or
  /// an em dash for "not enough data".
  final String value;

  /// What this number is over, when it is not self-evident — a rate's
  /// denominator, say. It sits INSIDE the tile because a caption under the
  /// grid qualifies every tile in it, which is how "Rates over 8 ended cases"
  /// came to read as a statement about the intake count too (federfall-v5di).
  /// Where the grid wraps is a function of the window, so there is no position
  /// beside the tiles that stays beside them.
  final String? note;

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
              if (note case final note?) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  note,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Lays [tiles] out as a grid of equal-width, equal-height [KpiCard]s: two
/// columns on a phone, more as the window earns them.
///
/// The width comes from the incoming constraints rather than a fixed number, so
/// tiles grow with the pane and a long label at a large text scale gets room to
/// wrap instead of overflowing. The column count follows from a minimum
/// readable tile rather than the window class: five tiles in two columns is
/// three rows of scrolling on a desktop, and a tile stretched to 600px is a
/// number lost in a field of white.
///
/// Rows are laid out one at a time under an [IntrinsicHeight] rather than as
/// one `Wrap`, because a `Wrap` gives every child its own height: at 400px the
/// dashboard's own labels rendered 176px and 196px tiles side by side — "Active
/// cases" fits on one line and "Intakes this year" wraps to two — leaving each
/// row ragged along the bottom. The tallest tile in a row now sets the height
/// for that row, so the cards read as one grid while still sizing to their
/// content (a fixed aspect ratio would clip the very labels that cause this).
class KpiGrid extends StatelessWidget {
  const KpiGrid(this.tiles, {super.key});

  final List<KpiCard> tiles;

  /// Narrowest a tile may be before the grid drops a column.
  static const double _minTileWidth = 240;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fits = (constraints.maxWidth / _minTileWidth).floor();
        // Never fewer than two (a single column of tiles is a list, not a
        // grid) and never more than four (past that the eye stops reading a
        // row and starts scanning a table).
        final columns = fits.clamp(2, 4);
        final rows = <Widget>[];
        for (var start = 0; start < tiles.length; start += columns) {
          final end = start + columns;
          final row = tiles.sublist(
            start,
            end > tiles.length ? tiles.length : end,
          );
          if (rows.isNotEmpty) {
            rows.add(const SizedBox(height: AppSpacing.md));
          }
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < columns; i++) ...[
                    if (i > 0) const SizedBox(width: AppSpacing.md),
                    // A short last row keeps its columns: the empty slots hold
                    // their share of the width so a lone final tile stays tile
                    // -sized instead of stretching across the whole grid.
                    Expanded(
                      child: i < row.length ? row[i] : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        );
      },
    );
  }
}
