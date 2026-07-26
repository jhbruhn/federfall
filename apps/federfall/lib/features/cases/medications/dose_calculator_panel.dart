import 'dart:async';

import 'package:federfall/features/cases/medications/medications_providers.dart';
import 'package:federfall/features/cases/weights/weights_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A dose the carer accepted from the calculator, with the inputs it came from
/// so the record can say why (federfall-6d3a.2).
typedef CalculatedDose = ({
  double amount,
  String unit,
  double? weightGUsed,
  double? volumeMl,
});

/// The dose calculator, folded into the sheet that logs a dose
/// (federfall-6d3a.1).
///
/// Deliberately not a screen or sheet of its own: a calculator you have to go
/// and find is a calculator done on paper instead. It sits collapsed under the
/// dose field, reads the bird's newest weight itself, and hands the result
/// over only when the carer taps — the derivation stays visible so it can be
/// checked against the paper protocol.
///
/// It asks for exactly the two things the carer is holding (federfall-6d3a.4)
/// — the prescription's rate in `mg/kg` and the product's strength in `mg/ml` —
/// and works out the rest: weight from the record, then the amount and the
/// volume to draw. There is no mode to pick and no unit field of its own; it
/// reads the sheet's [unit] live, so there is one "Einheit" input in the form,
/// not two.
///
/// When the dose follows a prescription that carries a rate (federfall-6d3a.2),
/// [initialRate] and [initialConcentrationPerMl] seed the two fields from it.
/// The panel then opens expanded and applies the result itself: the vet
/// already decided the number, so making the carer confirm the vet's own
/// arithmetic is ceremony, not safety. The derivation stays on screen to be
/// checked against, and the dose field stays editable.
///
/// It does NOT pre-apply from a stale weight — that is precisely where a number
/// would be a guess, so the warning shows and the field is left empty.
class DoseCalculatorPanel extends ConsumerStatefulWidget {
  const DoseCalculatorPanel({
    required this.caseId,
    required this.unit,
    required this.onApply,
    this.initialRate,
    this.initialConcentrationPerMl,
    this.enabled = true,
    super.key,
  });

  final String caseId;

  /// The sheet's unit field, read live for the `mg/kg` and `mg/ml` suffixes and
  /// handed back with the amount by [onApply].
  final TextEditingController unit;

  /// Seeds from the prescription this dose follows, when it carries them.
  final double? initialRate;
  final double? initialConcentrationPerMl;

  /// Called with the accepted dose for the caller to put into its own fields —
  /// the amount and unit to record, plus what it was derived from.
  final void Function(CalculatedDose dose) onApply;

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

  /// Anchors the scroll-into-view when the panel opens.
  final GlobalKey _panelKey = GlobalKey();

  bool _seeded = false;
  bool _autoApplied = false;

  /// Seeded from a prescription's own rate, so the panel starts open and its
  /// result is offered without a tap.
  bool get _fromPlan => widget.initialRate != null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Seeded here rather than in initState: the numbers are written with the
    // locale's decimal separator, which needs Localizations.
    if (_seeded) return;
    _seeded = true;
    final l10n = context.l10n;
    final rate = widget.initialRate;
    final concentration = widget.initialConcentrationPerMl;
    if (rate != null) _rate.text = formatDose(l10n, rate, null);
    if (concentration != null) {
      _concentration.text = formatDose(l10n, concentration, null);
    }
  }

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

  /// Hands a prescription's own dose to the sheet, once, as soon as the weight
  /// it needs has loaded — so logging a planned dose is open and save.
  ///
  /// Skipped on a stale weight: pre-filling a number derived from a weight
  /// nobody has checked is the one thing this path exists to prevent. The carer
  /// can still accept it by hand, having seen the warning.
  void _maybeAutoApply(DoseCalculation result, String unit, Weight? weight) {
    if (!_fromPlan || _autoApplied || !widget.enabled) return;
    if (!result.hasAmount) return;
    if (result.warnings.contains(DoseWarning.staleWeight)) return;
    _autoApplied = true;
    // After this frame: onApply calls setState on the sheet above.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onApply((
        amount: result.amount!,
        unit: unit,
        weightGUsed: weight?.weightG,
        volumeMl: result.volumeMl,
      ));
    });
  }

  @override
  Widget build(BuildContext context) {
    // Rebuilds when the sheet's unit field changes: it labels every number
    // here, and the panel keeps no copy of it.
    return ListenableBuilder(
      listenable: widget.unit,
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

    final rate = _number(_rate);
    final result = rate == null
        ? const DoseCalculation()
        : calculateDose(
            rate: rate,
            weightG: weight?.weightG,
            weighedAt: weighedAt,
            concentrationPerMl: _number(_concentration),
          );

    _maybeAutoApply(result, unit, weight);

    return Card(
      key: _panelKey,
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        initiallyExpanded: _fromPlan,
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
          // The two things the carer reads off a prescription and a bottle.
          // Everything else — the weight, the mg, the ml — the app knows or
          // works out; there is no mode to choose.
          _NumberField(
            controller: _rate,
            label: l10n.doseCalcRate,
            hintText: l10n.doseCalcRateHint,
            suffixText: '$unit/kg',
            enabled: widget.enabled,
            onChanged: (_) => setState(() {}),
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
          for (final warning in result.warnings) ...[
            const SizedBox(height: AppSpacing.sm),
            _Warning(text: _warningText(l10n, warning, result, unit)),
          ],
          const SizedBox(height: AppSpacing.sm),
          // Result and action share a line: the calculator is a scratchpad
          // inside a form, and every row it takes pushes the actual record
          // fields off screen.
          Row(
            children: [
              Expanded(
                child: result.hasAmount
                    ? DoseDerivation(
                        rate: rate!,
                        unit: unit,
                        weight: weight,
                        result: result,
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(width: AppSpacing.sm),
              // The app theme makes filled buttons full-width
              // (`minimumSize: Size.fromHeight(48)`, i.e. an infinite minimum
              // width). That is right for a form's primary action but
              // unsatisfiable for a non-flex child of a Row — it fails layout
              // and the Card's clip swallows the whole panel — so this one
              // asks for the Material default width.
              FilledButton.tonal(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(64, 48),
                ),
                onPressed: widget.enabled && result.hasAmount
                    ? () => widget.onApply((
                        amount: result.amount!,
                        unit: unit,
                        weightGUsed: weight?.weightG,
                        volumeMl: result.volumeMl,
                      ))
                    : null,
                child: Text(l10n.doseCalcApply),
              ),
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
class DoseDerivation extends StatelessWidget {
  const DoseDerivation({
    required this.rate,
    required this.unit,
    required this.weight,
    required this.result,
    super.key,
  });

  final double rate;
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

    // `20 mg/kg × 262 g` — the arithmetic behind the amount.
    final workedOut = w == null
        ? null
        : '${formatDose(l10n, rate, '$unit/kg')} × '
              '${formatWeightG(l10n, w.weightG)}';
    final answer = volume == null ? amount : formatDose(l10n, volume, 'ml');
    final detail = volume == null
        ? workedOut
        : [?workedOut, amount].join(' = ');

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
