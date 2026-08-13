import 'package:federfall/features/cases/cases_labels.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// The most days of the WHOLE course drawn as markers.
///
/// A course longer than this stops being a shape and becomes a wall of dots
/// nobody counts, so it degrades to one cycle plus a multiplier.
const int _maxDrawnDays = 56;

/// The most days of a SINGLE cycle drawn, once the course has degraded.
///
/// Past this even one round is unreadable and the strip is dropped entirely.
/// The written label is always there, so nothing is lost either way.
const int _maxDrawnCycleDays = 31;

/// How many rounds to draw when the course has no end.
///
/// One would not read as a repetition. Two shows the rhythm restarting, which
/// is the whole claim, and the trailing ellipsis says it keeps going.
const int _openEndedCycles = 2;

/// A medication's give/pause course, drawn (federfall-wmbi).
///
/// Two numbers in two fields do not read as a pattern — "5 and 2" is arithmetic
/// until five filled days and two empty ones are sitting there. This is that
/// picture, and it exists to catch the transposed pair (2 on / 5 off) at the
/// moment it is typed rather than in the worklist a week later.
///
/// It draws the WHOLE course, not one round: how long a bird is on a drug is
/// the question being answered, and a single round with "× 3" beside it just
/// hands the multiplication back to the reader. The rounds stay legible through
/// a wider gap between them.
///
/// The last round deliberately ends on its final GIVING day, with no trailing
/// pause — which is exactly where [repeats] puts the prescription's end date. A
/// pause after the last dose would be two days of a plan under which nothing is
/// ever due, and the picture is the clearest place to say so.
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
  /// what the prescription's dates work out to. Null draws an open-ended
  /// rhythm instead.
  final int? repeats;

  /// Days drawn for the full course: every round, minus the last one's pause.
  int get _courseDays =>
      (repeats ?? _openEndedCycles) * (onDays + offDays) -
      (repeats == null ? 0 : offDays);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    final caption = <String>[
      medicationCycleLabel(l10n, onDays, offDays),
      if (repeats case final n?) l10n.medCycleRepeatsCount(n),
    ].join(' · ');

    final strip = _strip(theme);

    return Semantics(
      // The strip is decoration over a sentence the reader can already get; a
      // screen reader gets the sentence and none of the dots.
      label: caption,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (strip != null) ...[strip, const SizedBox(height: AppSpacing.xs)],
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

  /// The marker strip, or null when even one round is too long to draw.
  Widget? _strip(ThemeData theme) {
    final full = _courseDays <= _maxDrawnDays;
    if (!full && onDays + offDays > _maxDrawnCycleDays) return null;

    final rounds = full ? (repeats ?? _openEndedCycles) : 1;
    // Open-ended, or one round standing in for many: both keep their trailing
    // pause, because in both cases the rhythm continues past what is drawn.
    final trimLast = full && repeats != null;

    final marks = <Widget>[];
    for (var round = 0; round < rounds; round++) {
      final isLast = round == rounds - 1;
      for (var day = 0; day < onDays; day++) {
        marks.add(const CycleDayMark(giving: true));
      }
      if (!(isLast && trimLast)) {
        for (var day = 0; day < offDays; day++) {
          marks.add(const CycleDayMark(giving: false));
        }
        if (!isLast) marks.add(const SizedBox(width: AppSpacing.sm));
      }
    }

    final trailing = switch ((full, repeats)) {
      // The rhythm has no end: say so rather than implying it stops here.
      (_, null) => '…',
      // Degraded to one round: hand back the multiplication, since the picture
      // can no longer carry it.
      (false, final n?) => '× $n',
      _ => null,
    };
    if (trailing != null) {
      marks.add(
        Padding(
          padding: const EdgeInsets.only(left: AppSpacing.xs),
          child: Text(
            trailing,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: marks,
    );
  }
}

/// One day of the course: filled when the drug is given, outlined when not.
///
/// Filled-vs-outlined carries the meaning, not hue — the two states must stay
/// apart for a reader who cannot separate the colours, and on both surfaces.
///
/// Public so a test can count what was actually drawn; a course's length is the
/// claim this widget makes, and asserting it any other way asserts nothing.
class CycleDayMark extends StatelessWidget {
  const CycleDayMark({required this.giving, super.key});

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
