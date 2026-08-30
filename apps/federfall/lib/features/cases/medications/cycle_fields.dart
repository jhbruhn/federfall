import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Whether a stored pair really describes a rhythm.
///
/// The server refuses a day count below 1 (1700000090) and `medication_due`
/// ignores half a pair, so this is the same reading, in the form. It is also
/// the second line of defence behind `pbCount`: PocketBase has no null for a
/// number field, and a `0` that reached a model here would switch the cycle ON
/// over two zeroes the form then refuses to save — which is exactly what every
/// catalogue entry without a rhythm used to do.
bool isCyclePair(int? on, int? off) =>
    on != null && off != null && on > 0 && off > 0;

/// A count worth showing in a field: anything below 1 renders empty rather than
/// as a zero somebody has to notice and clear.
String cycleCountText(int? value) =>
    (value == null || value < 1) ? '' : '$value';

/// The rhythm the two fields describe, or `(null, null)`.
///
/// Only a complete, positive pair counts, so the server never stores half a
/// rhythm the view would ignore.
(int?, int?) cycleDaysOf(
  TextEditingController onDays,
  TextEditingController offDays,
) {
  final on = int.tryParse(onDays.text.trim());
  final off = int.tryParse(offDays.text.trim());
  if (on == null || off == null || on < 1 || off < 1) return (null, null);
  return (on, off);
}

/// The give/pause pair, validated AS a pair, plus the line that says what
/// leaving it empty will do.
///
/// The two halves are only meaningful together — the server reads a half pair
/// as no rhythm at all (1700000090) — so the rule is: both empty is fine (that
/// is simply no cycle, saved as none), one filled makes the other required, and
/// a number below 1 is refused with the reason rather than a bare "required".
///
/// Validating each half on its own is what made this a trap: switching the
/// rhythm on and then thinking better of it left two empty, invalid fields and
/// no way to save except finding the switch again. `0` is refused on purpose —
/// a course with no pause is the switch being off, not a zero in a box — but
/// the message has to say so, because "Pflichtfeld" on a field somebody has
/// just filled in explains nothing (federfall-sh9e).
///
/// Each half reads its sibling's controller inside its own validator, so the
/// rule holds at save time whether or not the form rebuilt in between.
class CycleDaysPair extends StatelessWidget {
  const CycleDaysPair({
    required this.onDays,
    required this.offDays,
    required this.enabled,
    required this.onChanged,
    super.key,
  });

  final TextEditingController onDays;
  final TextEditingController offDays;
  final bool enabled;
  final ValueChanged<String> onChanged;

  bool get _unset => onDays.text.trim().isEmpty && offDays.text.trim().isEmpty;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _CycleDaysField(
                controller: onDays,
                other: offDays,
                label: l10n.medCycleOnDays,
                enabled: enabled,
                onChanged: onChanged,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _CycleDaysField(
                controller: offDays,
                other: onDays,
                label: l10n.medCycleOffDays,
                enabled: enabled,
                onChanged: onChanged,
              ),
            ),
          ],
        ),
        // Says what the empty pair will do, since it saves instead of
        // blocking: a rhythm nobody filled in is no rhythm.
        if (_unset) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.medCycleEmptyHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// One half of the give/pause pair. See [CycleDaysPair] for the rule.
class _CycleDaysField extends StatelessWidget {
  const _CycleDaysField({
    required this.controller,
    required this.other,
    required this.label,
    required this.enabled,
    required this.onChanged,
  });

  final TextEditingController controller;

  /// The other half — an empty value here is only acceptable while that one is
  /// empty too.
  final TextEditingController other;

  final String label;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppTextField(
      controller: controller,
      label: label,
      prefixIcon: Icons.calendar_view_week_outlined,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      enabled: enabled,
      onChanged: onChanged,
      validator: (v) {
        final text = (v ?? '').trim();
        if (text.isEmpty) {
          return other.text.trim().isEmpty ? null : l10n.fieldRequired;
        }
        final n = int.tryParse(text);
        return (n == null || n < 1) ? l10n.medCycleDaysMin : null;
      },
    );
  }
}

/// The course length, counted in rounds of the rhythm.
///
/// Empty is legitimate — a schedule that runs until somebody ends it — but a
/// count of rounds of a rhythm that is not there counts nothing, and used to be
/// dropped in silence on save (federfall-sh9e). It is refused with the reason
/// instead, rather than hidden until the pair is complete: a field that appears
/// and vanishes mid-typing is worse than one that explains itself.
class CycleRepeatsField extends StatelessWidget {
  const CycleRepeatsField({
    required this.controller,
    required this.onDays,
    required this.offDays,
    required this.enabled,
    required this.onChanged,
    required this.help,
    super.key,
  });

  final TextEditingController controller;
  final TextEditingController onDays;
  final TextEditingController offDays;
  final bool enabled;
  final ValueChanged<String> onChanged;

  /// What the count does in THIS form — it sets an end date on a prescription
  /// and is only a default on a catalogue entry.
  final String help;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppTextField(
          controller: controller,
          label: l10n.medCycleRepeats,
          prefixIcon: Icons.restart_alt_outlined,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          enabled: enabled,
          onChanged: onChanged,
          validator: (v) {
            if ((v ?? '').trim().isEmpty) return null;
            final (on, _) = cycleDaysOf(onDays, offDays);
            return on == null ? l10n.medCycleRepeatsNeedsDays : null;
          },
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          help,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
