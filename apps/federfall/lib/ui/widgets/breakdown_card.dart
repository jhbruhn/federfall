import 'package:federfall/ui/ui.dart';
import 'package:flutter/material.dart';

/// One labelled quantity to plot in a [BreakdownCard]'s chart. Kept structural
/// so the charts do not depend on where the numbers came from — and shared, so
/// a card's chart and its rows speak of the same thing.
@immutable
class ChartEntry {
  const ChartEntry(this.label, this.count);

  final String label;
  final int count;
}

/// One row of a [BreakdownCard]: a label, its count, and — when the records
/// behind that number can be listed — the tap that goes and lists them.
@immutable
class BreakdownRow {
  const BreakdownRow(this.label, this.count, {this.subtitle, this.onTap});

  final String label;
  final int count;

  /// Optional second line under [label] (e.g. a role), rendered muted.
  final String? subtitle;

  /// Null for a bucket no filter can express. The chevron follows this, so a
  /// row never promises a destination it does not have (as [KpiCard] does).
  final VoidCallback? onTap;
}

/// A titled card listing label · count rows, sorted by the caller. Each row
/// taps through to the records it counts, the way the dashboard KPIs do — a
/// number the user can't ask "which ones?" about is a dead end
/// (federfall-5puj).
///
/// Shared by the statistics breakdowns and the dashboard's carer workload
/// (federfall-9mit) — the same object should not be drawn two ways.
class BreakdownCard extends StatelessWidget {
  const BreakdownCard({
    required this.title,
    required this.rows,
    required this.emptyMessage,
    this.chart,
    this.footnote,
    super.key,
  });

  final String title;
  final List<BreakdownRow> rows;

  /// Optional plot of the same numbers, drawn under the title and above the
  /// rows. The rows stay either way: a chart shows the shape, the rows answer
  /// "how many exactly" and "which ones" — see [BreakdownPie] and
  /// [BreakdownBars].
  final Widget? chart;

  /// Shown in place of the rows when [rows] is empty.
  final String emptyMessage;

  /// Optional muted line under the rows, for what the card leaves out — a
  /// caller that filters uninteresting rows away can still say how many
  /// (the carer workload card's members with no open cases, federfall-06v1).
  /// Ignored when [rows] is empty: there the empty message is the whole
  /// answer, and the caller owns what it says.
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      // The rows ripple edge to edge, so the card has to clip them.
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: Text(title, style: theme.textTheme.titleMedium),
          ),
          if (chart case final chart? when rows.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              child: chart,
            ),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.md,
              ),
              child: Text(
                emptyMessage,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else ...[
            for (final row in rows) _BreakdownTile(row),
            if (footnote case final footnote?)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.xs,
                  AppSpacing.md,
                  0,
                ),
                child: Text(
                  footnote,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _BreakdownTile extends StatelessWidget {
  const _BreakdownTile(this.row);

  final BreakdownRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = row.subtitle;
    return InkWell(
      onTap: row.onTap,
      child: ConstrainedBox(
        // A real touch target, not just a line of text.
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(row.label),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              Text('${row.count}', style: theme.textTheme.titleMedium),
              const SizedBox(width: AppSpacing.xs),
              // Reserved even without a chevron, so the counts of a card whose
              // rows aren't uniformly tappable still line up in one column.
              SizedBox(
                width: 18,
                child: row.onTap == null
                    ? null
                    : Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
