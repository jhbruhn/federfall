import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/features/cases/medications/dose_calculator_panel.dart';
import 'package:federfall/features/cases/medications/medication_products_providers.dart';
import 'package:federfall/features/cases/medications/medication_routes_providers.dart';
import 'package:federfall/features/cases/medications/medications_providers.dart';
import 'package:federfall/features/cases/weights/weights_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the prescription (medication plan) add/edit form as a modal sheet.
Future<bool?> showPrescriptionSheet(
  BuildContext context, {
  required String caseId,
  Medication? plan,
}) {
  return showAppSheet<bool>(
    context,
    builder: (_) => PrescriptionSheet(caseId: caseId, plan: plan),
  );
}

/// Form for a vet's medication plan (FED-4.6): drug, dose, route, frequency,
/// start/end dates, controlled flag, instructions and prescriber.
class PrescriptionSheet extends ConsumerStatefulWidget {
  const PrescriptionSheet({required this.caseId, this.plan, super.key});

  final String caseId;
  final Medication? plan;

  @override
  ConsumerState<PrescriptionSheet> createState() => _PrescriptionSheetState();
}

class _PrescriptionSheetState extends ConsumerState<PrescriptionSheet>
    with DiscardGuard, FormSheetState {
  late final TextEditingController _drug;
  late final TextEditingController _dose;
  late final TextEditingController _unit;
  late final TextEditingController _concentration;
  late final TextEditingController _customHours;
  late final TextEditingController _cycleOn;
  late final TextEditingController _cycleOff;
  late final TextEditingController _cycleRepeats;
  late final TextEditingController _instructions;
  late final TextEditingController _prescribedBy;
  String? _route;
  late _FreqPreset _preset;

  /// Whether this plan runs a give/pause rhythm (federfall-wmbi). Held apart
  /// from the two day counts so switching it off keeps what was typed, and so a
  /// half-filled pair can never be saved as a cycle.
  bool _useCycle = false;
  late DateTime _startedAt;
  DateTime? _endedAt;
  bool _controlled = false;

  bool _doseSeeded = false;

  /// Whether the dose above is per kilogram of body weight rather than a flat
  /// amount. The two are alternatives, so they share one number field: a
  /// prescription says either "0.5 mg" or "20 mg/kg", never both.
  bool _perKg = false;

  String? _dateError;

  /// The catalogue entry this plan was written from, when one was picked. Held
  /// only in memory: it supplies defaults and the advisory range, and the plan
  /// itself stands on its own numbers afterwards.
  MedicationProduct? _product;

  bool get _isEditing => widget.plan != null;

  @override
  void initState() {
    super.initState();
    final p = widget.plan;
    _drug = TextEditingController(text: p?.drug ?? '');
    _dose = TextEditingController();
    _unit = TextEditingController(text: p?.doseUnit ?? '');
    _concentration = TextEditingController();
    _instructions = TextEditingController(text: p?.instructions ?? '');
    _prescribedBy = TextEditingController(text: p?.prescribedBy ?? '');
    _route = p?.route;
    _preset = _FreqPreset.from(p?.frequencyKind, p?.intervalHours);
    _customHours = TextEditingController(
      text: _preset == _FreqPreset.custom ? '${p?.intervalHours ?? ''}' : '',
    );
    _startedAt = (p?.startedAt ?? p?.created)?.toLocal() ?? DateTime.now();
    _endedAt = p?.endedAt?.toLocal();
    _controlled = p?.isControlled ?? false;

    // Half a pair is no cycle — the same reading `medication_due` takes.
    _useCycle = p?.cycleOnDays != null && p?.cycleOffDays != null;
    _cycleOn = TextEditingController(text: '${p?.cycleOnDays ?? ''}');
    _cycleOff = TextEditingController(text: '${p?.cycleOffDays ?? ''}');
    _cycleRepeats = TextEditingController(text: '${_derivedRepeats() ?? ''}');
  }

  /// The number of cycles the stored dates already describe, or null when they
  /// do not divide evenly (a hand-picked end date, or no end at all).
  ///
  /// The count is deliberately NOT stored: a plan is start + rhythm + end, and
  /// a fourth number could only ever contradict the other three. It is a
  /// calculator for the end date, so it is derived back the same way it was
  /// applied — see [_recomputeEnd] for why whole days are the right unit.
  int? _derivedRepeats() {
    final ended = _endedAt;
    final on = int.tryParse(_cycleOn.text.trim());
    final off = int.tryParse(_cycleOff.text.trim());
    if (!_useCycle || ended == null || on == null || off == null) return null;
    if (on < 1 || off < 1) return null;
    final days = ended.difference(_startedAt).inDays;
    final length = on + off;
    // days = repeats * length - off, inverted.
    if ((days + off) % length != 0) return null;
    final repeats = (days + off) ~/ length;
    return repeats < 1 ? null : repeats;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Not in initState: the dose is written with the locale's decimal
    // separator, and Localizations can only be read once dependencies exist.
    if (_doseSeeded) return;
    _doseSeeded = true;
    final l10n = context.l10n;
    final p = widget.plan;
    // A stored rate wins: a plan that has one was written as a rate.
    if (p?.doseRate != null) {
      _perKg = true;
      _dose.text = formatDose(l10n, p!.doseRate, null);
    } else if (p?.dose != null) {
      _dose.text = formatDose(l10n, p!.dose, null);
    }
    if (p?.concentrationPerMl != null) {
      _concentration.text = formatDose(l10n, p!.concentrationPerMl, null);
    }
  }

  @override
  void dispose() {
    for (final c in [
      _drug,
      _dose,
      _unit,
      _concentration,
      _customHours,
      _cycleOn,
      _cycleOff,
      _cycleRepeats,
      _instructions,
      _prescribedBy,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!(formKey.currentState?.validate() ?? false)) return;
    // Both ends carry a time of day, so "stops before it starts" is now easy to
    // type — and `medication_due` would treat such a plan as already over.
    final ended = _endedAt;
    if (ended != null && ended.isBefore(_startedAt)) {
      setState(() => _dateError = context.l10n.fieldEndBeforeStart);
      return;
    }
    setState(() => _dateError = null);

    final ok = await runSave(() async {
      final (_, org) = await requireUserOrg();
      final repo = await ref.read(medicationsRepositoryProvider.future);
      final amount = double.tryParse(_dose.text.trim().replaceAll(',', '.'));
      // The one number lands in whichever column it was entered as, and the
      // other is cleared so a plan never carries a stale second dosing rule.
      final dose = _perKg ? null : amount;
      final doseRate = _perKg ? amount : null;
      final concentration = double.tryParse(
        _concentration.text.trim().replaceAll(',', '.'),
      );
      final intervalHours = _preset == _FreqPreset.custom
          ? int.tryParse(_customHours.text.trim())
          : _preset.interval;
      final (cycleOn, cycleOff) = _cycle;

      final body = <String, dynamic>{
        'drug': _drug.text.trim(),
        'dose': dose,
        'dose_unit': trimToNull(_unit) ?? '',
        'dose_rate': doseRate,
        'concentration_per_ml': concentration,
        'frequency_kind': _preset.kind.wire,
        'interval_hours': intervalHours,
        'cycle_on_days': cycleOn,
        'cycle_off_days': cycleOff,
        'route': _route ?? '',
        'started_at': _startedAt.toUtc().toIso8601String(),
        'ended_at': _endedAt?.toUtc().toIso8601String() ?? '',
        'is_controlled': _controlled,
        'instructions': trimToNull(_instructions) ?? '',
        'prescribed_by': trimToNull(_prescribedBy) ?? '',
      };

      final plan = widget.plan;
      if (plan == null) {
        await repo.create({...body, 'case': widget.caseId, 'org': org});
      } else {
        await repo.update(plan.id, body);
      }

      ref.invalidate(caseBundleProvider(widget.caseId));
    });
    if (ok && mounted) Navigator.of(context).pop(true);
  }

  /// The rhythm to save: both day counts, or (null, null).
  ///
  /// Only a plan on a real interval can carry one — a cycle qualifies "every N
  /// hours" and means nothing without it — and only a complete, positive pair
  /// counts, so the server never stores half a rhythm the view would ignore.
  (int?, int?) get _cycle {
    if (!_useCycle || _preset.kind != MedicationFrequencyKind.scheduled) {
      return (null, null);
    }
    final on = int.tryParse(_cycleOn.text.trim());
    final off = int.tryParse(_cycleOff.text.trim());
    if (on == null || off == null || on < 1 || off < 1) return (null, null);
    return (on, off);
  }

  /// Rewrites the end date from the cycle count, whenever a number the count
  /// depends on changes. A count of "3" over 5-on/2-off means three rounds of
  /// giving, so the plan ends after the LAST GIVING day — the trailing pause is
  /// dropped rather than kept as two days in which nothing is due.
  ///
  /// `Duration(days:)` is exact 24-hour spans, not calendar days, which is
  /// precisely the unit the server's cycle uses (it counts from the start
  /// instant, so the rhythm survives a DST change instead of sliding an hour).
  void _recomputeEnd() {
    final (on, off) = _cycle;
    final repeats = int.tryParse(_cycleRepeats.text.trim());
    if (on == null || off == null || repeats == null || repeats < 1) return;
    setState(() {
      _endedAt = _startedAt.add(Duration(days: repeats * (on + off) - off));
      _dateError = null;
    });
  }

  /// The start carries a time of day: `medication_due` uses it as the first
  /// next-due, so a date-only start would flag a fresh plan "overdue since
  /// midnight". A future start expresses "first dose tonight".
  Future<void> _pickStarted() async {
    final picked = await pickDateTime(
      context,
      initial: _startedAt,
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _startedAt = picked);
      // The cycle is anchored at the start, so moving it moves the end the
      // count described.
      _recomputeEnd();
      markDirty();
    }
  }

  Future<void> _pickEnded() async {
    final picked = await pickDateTime(
      context,
      initial: _endedAt ?? _startedAt,
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _endedAt = picked;
        // A hand-picked end outranks the calculator that produced the old one;
        // leaving the count standing would show a number this date no longer
        // means. It comes back by itself if the date happens to divide evenly.
        _cycleRepeats.text = '${_derivedRepeats() ?? ''}';
      });
      markDirty();
    }
  }

  /// Pours a catalogue entry into the form, replacing every field the catalogue
  /// owns — including clearing the ones this entry does not specify.
  ///
  /// Picking an entry is a deliberate "use this protocol", so it must not leave
  /// pieces of the previous pick behind: a drug dosed in ml/kg with the last
  /// drug's mg/ml strength still in the form would compute the volume of the
  /// wrong medicine. Everything stays editable afterwards — the entry is the
  /// org's usual protocol, not a lock.
  void _applyProduct(MedicationProduct? product) {
    if (product == null) return;
    setState(() {
      _product = product;
      final l10n = context.l10n;
      _drug.text = product.label;
      _unit.text = product.doseUnit ?? '';
      // An entry with a rate is by definition dosed per kilogram.
      _perKg = product.doseRate != null;
      _dose.text = product.doseRate == null
          ? ''
          : formatDose(l10n, product.doseRate, null);
      _concentration.text = product.concentrationPerMl == null
          ? ''
          : formatDose(l10n, product.concentrationPerMl, null);
      _route = product.route;
      // The frequency preset has no "unset" value, so an entry with no default
      // schedule leaves whatever is selected rather than inventing daily.
      if (product.frequencyKind != null) {
        _preset = _FreqPreset.from(
          product.frequencyKind,
          product.intervalHours,
        );
        _customHours.text = _preset == _FreqPreset.custom
            ? '${product.intervalHours ?? ''}'
            : '';
      }
      // The rhythm is part of the protocol, so it follows the frequency —
      // including being cleared, which is what an entry giving the drug
      // straight through has to mean. The cycle count is not the catalogue's
      // to decide: how long this bird gets it is a decision per case.
      _useCycle = product.cycleOnDays != null && product.cycleOffDays != null;
      _cycleOn.text = '${product.cycleOnDays ?? ''}';
      _cycleOff.text = '${product.cycleOffDays ?? ''}';
      _cycleRepeats.text = '${_derivedRepeats() ?? ''}';
    });
    markDirty();
  }

  /// Flags a per-kilogram rate outside the catalogue's advisory range for the
  /// picked product. Advisory on purpose: the vet in front of the bird outranks
  /// the list, so this warns and still saves.
  String? _rangeWarning(AppLocalizations l10n, String unit) {
    final product = _product;
    if (!_perKg || product == null) return null;
    final rate = double.tryParse(_dose.text.trim().replaceAll(',', '.'));
    if (rate == null || !product.isOutOfRange(rate)) return null;
    final u = unit.isEmpty ? '' : ' $unit/kg';
    final min = product.rateMin;
    final max = product.rateMax;
    final range = switch ((min, max)) {
      (final a?, final b?) =>
        '${formatNumber(l10n, a)}–${formatNumber(l10n, b)}$u',
      (final a?, null) => '≥ ${formatNumber(l10n, a)}$u',
      (null, final b?) => '≤ ${formatNumber(l10n, b)}$u',
      _ => '',
    };
    return l10n.medRateOutOfRange(product.label, range);
  }

  /// What the entered rate means for this bird today — the same derivation the
  /// carer will see when logging a dose, so a typo in the rate is obvious while
  /// writing the plan rather than at the syringe.
  Widget? _ratePreview(AppLocalizations l10n, String unit) {
    if (!_perKg) return null;
    final rate = double.tryParse(_dose.text.trim().replaceAll(',', '.'));
    if (rate == null) return null;
    final weights = ref.watch(weightsForCaseProvider(widget.caseId)).value;
    final weight = latestWeight(weights ?? const []);
    if (weight == null) return null;
    final result = calculateDose(
      rate: rate,
      weightG: weight.weightG,
      concentrationPerMl: double.tryParse(
        _concentration.text.trim().replaceAll(',', '.'),
      ),
    );
    if (!result.hasAmount) return null;
    return DoseDerivation(
      rate: rate,
      unit: unit.isEmpty ? 'mg' : unit,
      weight: weight,
      result: result,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final unit = _unit.text.trim();
    final preview = _ratePreview(l10n, unit);
    final products =
        ref.watch(activeMedicationProductsProvider).value ??
        const <MedicationProduct>[];
    final rangeWarning = _rangeWarning(l10n, unit);

    return guardUnsavedChanges(
      child: SheetScaffold(
        title: _isEditing
            ? l10n.prescriptionEditTitle
            : l10n.prescriptionNewTitle,
        formKey: formKey,
        onFormChanged: markDirty,
        isBusy: isBusy,
        error: saveError,
        onSave: _save,
        children: [
          _SectionTitle(l10n.medSectionDrug),
          // The catalogue is a prefill, never a constraint: the drug below
          // stays free text so an unlisted preparation is still prescribable.
          if (products.isNotEmpty) ...[
            DropdownButtonFormField<MedicationProduct>(
              initialValue: _product,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.medProductPicker,
                prefixIcon: const Icon(Icons.inventory_2_outlined),
              ),
              items: [
                for (final p in products)
                  DropdownMenuItem(value: p, child: Text(p.label)),
              ],
              onChanged: isBusy ? null : _applyProduct,
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          AppTextField(
            controller: _drug,
            label: l10n.medDrug,
            prefixIcon: Icons.medication_outlined,
            enabled: !isBusy,
            validator: Validators.required(l10n),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AppTextField(
                  controller: _dose,
                  label: l10n.medDose,
                  suffixText: unit.isEmpty
                      ? (_perKg ? '/kg' : null)
                      : (_perKg ? '$unit/kg' : unit),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp('[0-9.,]')),
                  ],
                  enabled: !isBusy,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: AppTextField(
                  controller: _unit,
                  label: l10n.medUnit,
                  enabled: !isBusy,
                ),
              ),
            ],
          ),
          // Reading the dose above per kilogram is what keeps the plan correct
          // as the bird gains weight: every dose re-derives from it, so a plan
          // written at 240 g still doses right at 330 g.
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.medPerKg),
            subtitle: Text(l10n.medPerKgHelp),
            value: _perKg,
            onChanged: isBusy
                ? null
                : (v) {
                    setState(() => _perKg = v);
                    markDirty();
                  },
          ),
          if (rangeWarning != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
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
                    rangeWarning,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          AppTextField(
            controller: _concentration,
            label: l10n.doseCalcConcentration,
            hintText: l10n.doseCalcConcentrationHint,
            suffixText: unit.isEmpty ? null : '$unit/ml',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp('[0-9.,]')),
            ],
            enabled: !isBusy,
            onChanged: (_) => setState(() {}),
          ),
          if (preview != null) ...[
            const SizedBox(height: AppSpacing.sm),
            preview,
          ],
          const SizedBox(height: AppSpacing.lg),
          _SectionTitle(l10n.medSectionGiving),
          MedicationRouteDropdown(
            value: _route,
            enabled: !isBusy,
            onChanged: (r) => setState(() => _route = r),
          ),
          const SizedBox(height: AppSpacing.md),
          DropdownButtonFormField<_FreqPreset>(
            initialValue: _preset,
            decoration: InputDecoration(
              labelText: l10n.medFrequency,
              prefixIcon: const Icon(Icons.repeat),
            ),
            items: [
              for (final p in _FreqPreset.values)
                DropdownMenuItem(value: p, child: Text(p.label(l10n))),
            ],
            onChanged: isBusy
                ? null
                : (p) => setState(() => _preset = p ?? _preset),
          ),
          if (_preset == _FreqPreset.custom) ...[
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              controller: _customHours,
              label: l10n.medIntervalHours,
              prefixIcon: Icons.timelapse_outlined,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              enabled: !isBusy,
              validator: (v) {
                final n = int.tryParse((v ?? '').trim());
                return (n == null || n <= 0) ? l10n.fieldRequired : null;
              },
            ),
          ],
          if (_preset.kind == MedicationFrequencyKind.scheduled) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.medCycle),
              subtitle: Text(l10n.medCycleHelp),
              value: _useCycle,
              onChanged: isBusy
                  ? null
                  : (v) {
                      setState(() => _useCycle = v);
                      markDirty();
                    },
            ),
            if (_useCycle) ...[
              const SizedBox(height: AppSpacing.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _CycleDays(
                      controller: _cycleOn,
                      label: l10n.medCycleOnDays,
                      enabled: !isBusy,
                      onChanged: (_) {
                        setState(() {});
                        _recomputeEnd();
                      },
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: _CycleDays(
                      controller: _cycleOff,
                      label: l10n.medCycleOffDays,
                      enabled: !isBusy,
                      onChanged: (_) {
                        setState(() {});
                        _recomputeEnd();
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                controller: _cycleRepeats,
                label: l10n.medCycleRepeats,
                prefixIcon: Icons.restart_alt_outlined,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                enabled: !isBusy,
                // Deliberately no validator: an empty count is a schedule that
                // runs until somebody ends it, which is a legitimate plan.
                onChanged: (_) => _recomputeEnd(),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                l10n.medCycleRepeatsHelp,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
          const SizedBox(height: AppSpacing.md),
          DateField(
            label: l10n.medStarted,
            value: _startedAt,
            enabled: !isBusy,
            showTime: true,
            onPick: _pickStarted,
          ),
          const SizedBox(height: AppSpacing.md),
          DateField(
            label: l10n.medEnded,
            value: _endedAt,
            enabled: !isBusy,
            showTime: true,
            errorText: _dateError,
            onPick: _pickEnded,
            onClear: () {
              setState(() => _endedAt = null);
              markDirty();
            },
            placeholder: l10n.caseDateNotSet,
          ),
          const SizedBox(height: AppSpacing.lg),
          _SectionTitle(l10n.medSectionRecord),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.medControlled),
            value: _controlled,
            onChanged: isBusy
                ? null
                : (v) {
                    setState(() => _controlled = v);
                    markDirty();
                  },
          ),
          AppTextField(
            controller: _instructions,
            label: l10n.medInstructions,
            enabled: !isBusy,
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _prescribedBy,
            label: l10n.medPrescribedBy,
            prefixIcon: Icons.local_hospital_outlined,
            enabled: !isBusy,
          ),
        ],
      ),
    );
  }
}

/// The frequency presets offered in the prescription form, each mapping to the
/// structured (kind, interval-hours) stored on the plan.
/// One half of the give/pause pair. Only ever built while the cycle is on, so
/// it can require a positive number outright — half a rhythm is not a rhythm,
/// and the server would silently ignore it.
class _CycleDays extends StatelessWidget {
  const _CycleDays({
    required this.controller,
    required this.label,
    required this.enabled,
    required this.onChanged,
  });

  final TextEditingController controller;
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
        final n = int.tryParse((v ?? '').trim());
        return (n == null || n <= 0) ? l10n.fieldRequired : null;
      },
    );
  }
}

enum _FreqPreset {
  once(MedicationFrequencyKind.once, null),
  daily(MedicationFrequencyKind.scheduled, 24),
  bid(MedicationFrequencyKind.scheduled, 12),
  tid(MedicationFrequencyKind.scheduled, 8),
  qid(MedicationFrequencyKind.scheduled, 6),
  eod(MedicationFrequencyKind.scheduled, 48),
  custom(MedicationFrequencyKind.scheduled, null),
  asNeeded(MedicationFrequencyKind.asNeeded, null);

  const _FreqPreset(this.kind, this.interval);

  final MedicationFrequencyKind kind;
  final int? interval;

  /// The preset matching a stored (kind, interval); defaults to [daily] when
  /// nothing is set, and to [custom] for an unrecognised interval.
  static _FreqPreset from(MedicationFrequencyKind? kind, int? interval) {
    switch (kind) {
      case null:
        return _FreqPreset.daily;
      case MedicationFrequencyKind.once:
        return _FreqPreset.once;
      case MedicationFrequencyKind.asNeeded:
        return _FreqPreset.asNeeded;
      case MedicationFrequencyKind.scheduled:
        return values.firstWhere(
          (p) =>
              p.kind == MedicationFrequencyKind.scheduled &&
              p.interval == interval &&
              p != _FreqPreset.custom,
          orElse: () => _FreqPreset.custom,
        );
    }
  }

  String label(AppLocalizations l10n) => switch (this) {
    _FreqPreset.once => l10n.freqOnce,
    _FreqPreset.daily => l10n.freqOnceDaily,
    _FreqPreset.bid => l10n.freqTwiceDaily,
    _FreqPreset.tid => l10n.freq3xDaily,
    _FreqPreset.qid => l10n.freq4xDaily,
    _FreqPreset.eod => l10n.freqEveryOtherDay,
    _FreqPreset.custom => l10n.freqCustom,
    _FreqPreset.asNeeded => l10n.freqAsNeeded,
  };
}

/// Optional route picker shared by the prescription and dose forms, populated
/// from the live `medication_routes` code list. [value] is a route id, or null.
class MedicationRouteDropdown extends ConsumerWidget {
  const MedicationRouteDropdown({
    required this.value,
    required this.enabled,
    required this.onChanged,
    super.key,
  });

  final String? value;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final decoration = InputDecoration(
      labelText: l10n.medRoute,
      prefixIcon: const Icon(Icons.vaccines_outlined),
    );
    // Active routes, plus the current selection even if it has been
    // deactivated, so an existing record's route stays visible.
    final options = (ref.watch(medicationRoutesProvider).value ?? const [])
        .where((r) => r.active || r.id == value)
        .toList(growable: false);
    return DropdownButtonFormField<String>(
      initialValue: options.any((r) => r.id == value) ? value : null,
      decoration: decoration,
      items: [
        for (final r in options)
          DropdownMenuItem(value: r.id, child: Text(r.label)),
      ],
      onChanged: enabled ? onChanged : null,
    );
  }
}

/// A form section heading, matching the one org settings uses: the prescription
/// has thirteen controls, and without grouping they all read as equally
/// important, unrelated fields.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
