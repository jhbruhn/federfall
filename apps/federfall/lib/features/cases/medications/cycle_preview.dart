import 'package:federfall/features/cases/cases_labels.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// The most days of one cycle drawn as markers.
///
/// Past this the strip stops being a shape and becomes a wall of dots that
/// nobody counts — a monthly rhythm is read off the numbers, not off 45 marks.
/// The written label is always there beside it, so nothing is lost.
const int _maxDrawnDays = 31;

/// One cycle of a medication's give/pause rhythm, drawn (federfall-wmbi).
///
/// Two numbers in two fields do not read as a pattern — "5 and 2" is arithmetic
/// until you see five filled days and two empty ones. This is that picture, and
/// it exists to catch the transposed pair (2 on / 5 off) at the moment it is
/// typed rather than in the worklist a week later.
///
/// Deliberately ONE cycle plus a multiplier rather than the whole course: the
/// repetition is the part the numbers already say clearly, and drawing three
/// identical rows would push the form's actual fields off the screen.
class MedicationCyclePreview extends StatelessWidget {
  const MedicationCyclePreview({
    required this.onDays,
    required this.offDays,
    this.repeats,
    super.key,
  });

  final int onDays;
  final int offDays;

  /// How many rounds, when that is known — the catalogue's course length, or
  /// what the prescription's dates work out to. Null renders no multiplier.
  final int? repeats;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final total = onDays + offDays;

    final caption = <String>[
      medicationCycleLabel(l10n, onDays, offDays),
      if (repeats case final n?) l10n.medCycleRepeatsCount(n),
    ].join(' · ');

    return Semantics(
      // The strip is decoration over a sentence the reader can already get; a
      // screen reader gets the sentence and none of the dots.
      label: caption,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (total <= _maxDrawnDays) ...[
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (var day = 0; day < total; day++)
                  _DayMark(giving: day < onDays),
                if (repeats case final n?)
                  Padding(
                    padding: const EdgeInsets.only(left: AppSpacing.xs),
                    child: Text(
                      '× $n',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          Text(
            caption,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// One day of the cycle: filled when the drug is given, outlined when not.
///
/// Filled-vs-outlined carries the meaning, not hue — the two states must stay
/// apart for a reader who cannot separate the colours, and on both surfaces.
class _DayMark extends StatelessWidget {
  const _DayMark({required this.giving});

  final bool giving;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: giving ? scheme.primary : Colors.transparent,
        border: giving ? null : Border.all(color: scheme.outline, width: 1.5),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}
