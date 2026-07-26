import 'dart:async';

import 'package:federfall/features/cases/medications/medications_providers.dart';
import 'package:federfall/features/cases/weights/weights_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The dose calculator, folded into the sheet that logs a dose
/// (federfall-6d3a.1).
///
/// Deliberately not a screen or sheet of its own: a calculator you have to go
/// and find is a calculator done on paper instead. It sits collapsed under the
/// dose field, reads the bird's newest weight itself, and hands the result
/// over only when the carer taps — the derivation stays visible so it can be
/// checked against the paper protocol.
///
/// It asks for nothing the form already knows (federfall-6d3a.4): it reads the
/// sheet's [dose] and [unit] fields live rather than keeping copies of them, so
/// there is one "Einheit" input in the sheet, not two. That also decides the
/// shape of each mode:
///
/// * per kilogram — the rate is the input, the amount is derived, and it lands
///   in the [dose] field only when the carer taps (via [onApply]).
/// * per bird — the flat dose in the [dose] field *is* the amount, so there is
///   no rate to ask for and nothing to apply. The calculator turns it into
///   millilitres and cross-checks it as mg/kg.
///
/// Nothing here is persisted. Storing the rate on the prescription (so a plan
/// follows the bird's weight as it recovers) is federfall-6d3a.2.
class DoseCalculatorPanel extends ConsumerStatefulWidget {
  const DoseCalculatorPanel({
    required this.caseId,
    required this.dose,
    required this.unit,
    required this.onApply,
    this.enabled = true,
    super.key,
  });

  final String caseId;

  /// The sheet's dose field: read as the amount for a flat per-bird dose, and
  /// the destination of [onApply] for a per-kilogram rate. Never written here.
  final TextEditingController dose;

  /// The sheet's unit field, read for the `mg/kg` and `mg/ml` suffixes.
  final TextEditingController unit;

  /// Called with the calculated amount and the unit it is in, for the caller to
  /// put into its own fields.
  final void Function(double amount, String unit) onApply;

  /// False while the sheet is saving, matching its other inputs.
  final bool enabled;

  @override
  ConsumerState<DoseCalculatorPanel> createState() =>
      _DoseCalculatorPanelState();
}

/// The unit almost every avian drug is dosed in; the carer can overwrite it.
const String _defaultUnit = 'mg';

class _DoseCalculatorPanelState extends ConsumerState<DoseCalculatorPanel> {
  final TextEditingController _rate = TextEditingController();
  final TextEditingController _concentration = TextEditingController();
  DoseBasis _basis = DoseBasis.perKilogram;

  /// Anchors the scroll-into-view when the panel opens.
  final GlobalKey _panelKey = GlobalKey();

  @override
  void dispose() {
    for (final c in [_rate, _concentration]) {
      c.dispose();
    }
    super.dispose();
  }

  double? _number(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '.'));

  /// Brings the opened panel into view.
  ///
  /// The calculator sits in the middle of a form that is taller than a small
  /// window, so unfolding it would otherwise happen entirely below the fold and
  /// tapping the header would look like it did nothing. The tile opens without
  /// an animation (see [AnimationStyle.noAnimation] below), so one frame later
  /// the children already have their final height and the scroll lands exactly
  /// right — no waiting on an animation to guess when to measure.
  void _revealOnExpand({required bool expanded}) {
    if (!expanded) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _panelKey.currentContext;
      if (ctx == null || !ctx.mounted) return;
      // Scrolls the least amount that puts the panel's bottom on screen, and
      // is a no-op both when it already fits and when there is no scrollable
      // ancestor at all.
      unawaited(
        Scrollable.ensureVisible(
          ctx,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // Rebuilds when the sheet's own dose or unit field changes, since both are
    // inputs to the calculation now that the panel keeps no copy of them.
    return ListenableBuilder(
      listenable: Listenable.merge([widget.dose, widget.unit]),
      builder: (context, _) => _buildPanel(context),
    );
  }

  Widget _buildPanel(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final materialL10n = MaterialLocalizations.of(context);

    final weights =
        ref.watch(weightsForCaseProvider(widget.caseId)).value ??
        const <Weight>[];
    final weight = latestWeight(weights);
    final weighedAt = weight?.measuredAt ?? weight?.created;

    // The record's unit drives every label here. It may be blank on an ad-hoc
    // dose, and a suffix reading "/kg" helps nobody, so the calculator works in
    // mg and says so — and writes that unit back with the dose on apply.
    final recordUnit = widget.unit.text.trim();
    final unit = recordUnit.isEmpty ? _defaultUnit : recordUnit;

    final perKg = _basis == DoseBasis.perKilogram;
    // Per kilogram the rate is the panel's own input; per bird the dose the
    // carer already typed above IS the amount, so there is nothing to ask for.
    final rate = perKg ? _number(_rate) : _number(widget.dose);

    final result = rate == null
        ? const DoseCalculation()
        : calculateDose(
            rate: rate,
            basis: _basis,
            weightG: weight?.weightG,
            weighedAt: weighedAt,
            concentrationPerMl: _number(_concentration),
          );

    final basisToggle = _BasisToggle(
      basis: _basis,
      enabled: widget.enabled,
      onChanged: (b) => setState(() => _basis = b),
    );

    return Card(
      key: _panelKey,
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        onExpansionChanged: (expanded) => _revealOnExpand(expanded: expanded),
        // Unfold instantly: an animated open would make the panel's height a
        // moving target for the scroll above, and there is nothing to admire
        // in a form panel sliding open.
        expansionAnimationStyle: AnimationStyle.noAnimation,
        leading: const Icon(Icons.calculate_outlined),
        title: Text(l10n.doseCalcTitle),
        subtitle: weight == null
            ? null
            : Text(
                '${formatWeightG(l10n, weight.weightG)} · '
                '${formatEventDate(materialL10n, weighedAt)}',
              ),
        // Top padding, unlike the usual zero: the first row is a text field
        // whose floating label would otherwise be clipped against the header.
        childrenPadding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.md,
        ),
        children: [
          if (perKg) ...[
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: _NumberField(
                    controller: _rate,
                    label: l10n.doseCalcRate,
                    hintText: l10n.doseCalcRateHint,
                    suffixText: '$unit/kg',
                    enabled: widget.enabled,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(flex: 2, child: basisToggle),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            _NumberField(
              controller: _concentration,
              label: l10n.doseCalcConcentration,
              hintText: l10n.doseCalcConcentrationHint,
              suffixText: '$unit/ml',
              enabled: widget.enabled,
              onChanged: (_) => setState(() {}),
            ),
          ] else
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: _NumberField(
                    controller: _concentration,
                    label: l10n.doseCalcConcentration,
                    hintText: l10n.doseCalcConcentrationHint,
                    suffixText: '$unit/ml',
                    enabled: widget.enabled,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(flex: 2, child: basisToggle),
              ],
            ),
          for (final warning in result.warnings) ...[
            const SizedBox(height: AppSpacing.sm),
            _Warning(text: _warningText(l10n, warning, result, unit)),
          ],
          const SizedBox(height: AppSpacing.sm),
          // Result and action share a line: the calculator is a scratchpad
          // inside a form, and every row it takes pushes the actual record
          // fields off screen. Per bird there is no action at all — the dose
          // is already in the field above — so the answer gets the full width.
          Row(
            children: [
              Expanded(
                child: result.hasAmount
                    ? _Derivation(
                        rate: rate!,
                        basis: _basis,
                        unit: unit,
                        weight: weight,
                        result: result,
                      )
                    : const SizedBox.shrink(),
              ),
              if (perKg) ...[
                const SizedBox(width: AppSpacing.sm),
                // The app theme makes filled buttons full-width
                // (`minimumSize: Size.fromHeight(48)`, i.e. an infinite
                // minimum width). That is right for a form's primary action
                // but unsatisfiable for a non-flex child of a Row — it fails
                // layout and the Card's clip swallows the whole panel — so
                // this one asks for the Material default width.
                FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(64, 48),
                  ),
                  onPressed: widget.enabled && result.hasAmount
                      ? () => widget.onApply(result.amount!, unit)
                      : null,
                  child: Text(l10n.doseCalcApply),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            l10n.doseCalcDisclaimer,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  String _warningText(
    AppLocalizations l10n,
    DoseWarning warning,
    DoseCalculation result,
    String unit,
  ) {
    switch (warning) {
      case DoseWarning.missingWeight:
        return l10n.doseCalcNoWeight;
      case DoseWarning.staleWeight:
        return l10n.doseCalcStaleWeight(doseWeightMaxAge.inDays);
      case DoseWarning.unmeasurableVolume:
        final factor = result.dilutionFactor ?? 1;
        return l10n.doseCalcDilute(
          factor,
          formatDose(
            l10n,
            roundToSignificantDigits((result.volumeMl ?? 0) * factor),
            'ml',
          ),
        );
    }
  }
}

/// The answer on top, the arithmetic that produced it underneath — symbols
/// rather than words, so it needs no translation and reads like the protocol
/// it is checked against.
///
/// Once a concentration is known, the millilitres are what the carer actually
/// does something with, so they take the lead and the amount drops to the
/// working-out line (`0.35 ml` over `20 mg/kg × 262 g = 5.24 mg`). Without a
/// concentration there is nothing to draw up and the amount is the answer.
///
/// For a flat per-bird dose the amount came from the sheet, so the working-out
/// line carries the cross-check instead: what that dose is per kilogram.
class _Derivation extends StatelessWidget {
  const _Derivation({
    required this.rate,
    required this.basis,
    required this.unit,
    required this.weight,
    required this.result,
  });

  final double rate;
  final DoseBasis basis;
  final String unit;
  final Weight? weight;
  final DoseCalculation result;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final amount = formatDose(l10n, result.amount, unit);
    final volume = result.volumeMl;
    final w = weight;

    // Per kilogram: `20 mg/kg × 262 g`, the arithmetic behind the amount.
    // Per bird: `= 1.91 mg/kg`, the cross-check on a dose typed by hand.
    final workedOut = switch (basis) {
      DoseBasis.perKilogram when w != null =>
        '${formatDose(l10n, rate, '$unit/kg')} × '
            '${formatWeightG(l10n, w.weightG)}',
      DoseBasis.perAnimal when result.ratePerKg != null =>
        '= ${formatDose(l10n, result.ratePerKg, '$unit/kg')}',
      _ => null,
    };
    final answer = volume == null ? amount : formatDose(l10n, volume, 'ml');
    final detail = switch ((volume, basis)) {
      (null, _) => workedOut,
      (_, DoseBasis.perAnimal) => [amount, ?workedOut].join('  ·  '),
      _ => [?workedOut, amount].join(' = '),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(answer, style: theme.textTheme.titleMedium),
        if (detail != null)
          Text(
            detail,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

class _Warning extends StatelessWidget {
  const _Warning({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.warning_amber_rounded,
          size: 20,
          color: theme.colorScheme.error,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ),
      ],
    );
  }
}

/// Whether the rate is per kilogram or a flat amount per bird. A dropdown
/// rather than a segmented button so it is the same height as the field beside
/// it and survives a narrow sheet without overflowing.
class _BasisToggle extends StatelessWidget {
  const _BasisToggle({
    required this.basis,
    required this.enabled,
    required this.onChanged,
  });

  final DoseBasis basis;
  final bool enabled;
  final ValueChanged<DoseBasis> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return DropdownButtonFormField<DoseBasis>(
      initialValue: basis,
      // Half a row wide next to the concentration field: let the value shrink
      // rather than overflow when the sheet is narrow.
      isExpanded: true,
      decoration: InputDecoration(labelText: l10n.doseCalcBasis),
      items: [
        DropdownMenuItem(
          value: DoseBasis.perKilogram,
          child: Text(l10n.doseCalcPerKg),
        ),
        DropdownMenuItem(
          value: DoseBasis.perAnimal,
          child: Text(l10n.doseCalcPerAnimal),
        ),
      ],
      onChanged: enabled ? (b) => onChanged(b ?? basis) : null,
    );
  }
}

/// A decimal input that also accepts the comma every German keyboard offers.
class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.label,
    required this.enabled,
    required this.onChanged,
    this.hintText,
    this.suffixText,
  });

  final TextEditingController controller;
  final String label;
  final String? hintText;
  final String? suffixText;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      controller: controller,
      label: label,
      hintText: hintText,
      suffixText: suffixText,
      enabled: enabled,
      onChanged: onChanged,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[0-9.,]'))],
    );
  }
}
