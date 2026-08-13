import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/cases_labels.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/features/cases/medications/medications_providers.dart';
import 'package:federfall/features/cases/weights/weights_providers.dart';
import 'package:federfall/features/worklist/worklist.dart';
import 'package:federfall/features/worklist/worklist_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the dose-round form for one drug's due doses. Resolves to the number
/// of doses logged, or null if nothing was saved.
Future<int?> showBatchAdministrationSheet(
  BuildContext context, {
  required MedicationDueGroup group,
}) {
  return showAppSheet<int>(
    context,
    builder: (_) => BatchAdministrationSheet(group: group),
  );
}

/// Give one drug to a whole group in one act (federfall-o3gz): every due bird
/// on its own row with its own amount, one shared moment, one transaction.
///
/// The rows are a SNAPSHOT of what the carer tapped, not a live list. Today's
/// worklist re-derives itself every minute, and a row appearing or vanishing
/// while somebody is holding a syringe is worse than a list a minute old.
///
/// The amount is per bird by necessity: `dose_rate` is prescribed per kilogram,
/// so one course over nine birds is nine different amounts. Each row prefills
/// from that bird's own newest weight, and — exactly like the single-dose
/// calculator — it refuses to prefill from a STALE weight, because a number
/// nobody checked is the failure this whole path exists to avoid. Such a row
/// still saves; it just asks for the amount.
class BatchAdministrationSheet extends ConsumerStatefulWidget {
  const BatchAdministrationSheet({required this.group, super.key});

  final MedicationDueGroup group;

  @override
  ConsumerState<BatchAdministrationSheet> createState() =>
      _BatchAdministrationSheetState();
}

class _BatchAdministrationSheetState
    extends ConsumerState<BatchAdministrationSheet>
    with DiscardGuard, FormSheetState {
  late final TextEditingController _notes;

  /// One editable amount per due, keyed by prescription id.
  final _amounts = <String, TextEditingController>{};

  /// The birds explicitly unticked. Held as the exception, so a row whose
  /// amount arrives late is included rather than silently skipped.
  final _excluded = <String>{};

  /// What each row's prefill was derived from, kept so a saved dose can say
  /// which weight produced it — and dropped the moment the carer types a
  /// different number, since the derivation would no longer describe it.
  final _derivations = <String, DoseCalculation>{};

  /// The newest weight per case, once loaded. Absent while loading and for a
  /// case that has never been weighed.
  final _weights = <String, Weight>{};

  bool _weightsLoaded = false;

  /// Set when the weights could not be fetched. Not fatal — the round still
  /// saves — but never silent: every rate-based prefill is missing because of
  /// it, and a blank dose field with no explanation reads as "no dose needed".
  bool _weightsFailed = false;

  late DateTime _administeredAt;

  /// One key for this sheet's whole lifetime: pressing save again after a
  /// timeout resubmits the SAME key, so the server replays the committed round
  /// instead of recording the group as dosed twice.
  final String _idempotencyKey = newIdempotencyKey();

  int _saved = 0;

  List<WorklistItem> get _dues => widget.group.givable;

  @override
  void initState() {
    super.initState();
    _notes = TextEditingController();
    _administeredAt = DateTime.now();
    for (final due in _dues) {
      _amounts[due.medication!.id] = TextEditingController();
    }
    // Fire and forget: the form is usable before the weights land, and every
    // outcome is reflected in state rather than thrown at the sheet.
    _loadWeights().ignore();
  }

  @override
  void dispose() {
    _notes.dispose();
    for (final c in _amounts.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Fetches every bird's weights in ONE request and seeds the amounts.
  Future<void> _loadWeights() async {
    try {
      final repo = await ref.read(weightsRepositoryProvider.future);
      final rows = await repo.byCases({for (final d in _dues) d.caseId});
      final byCase = <String, List<Weight>>{};
      for (final w in rows) {
        final caseId = w.caseId;
        if (caseId == null) continue;
        (byCase[caseId] ??= []).add(w);
      }
      if (!mounted) return;
      setState(() {
        for (final entry in byCase.entries) {
          final newest = latestWeight(entry.value);
          if (newest != null) _weights[entry.key] = newest;
        }
        _weightsLoaded = true;
      });
    } on Object {
      // Reported in the form, not swallowed and not thrown — see
      // [_weightsFailed].
      if (!mounted) return;
      setState(() {
        _weightsLoaded = true;
        _weightsFailed = true;
      });
      return;
    }
    if (mounted) _seedAmounts();
  }

  /// Writes the derived amount into every row that has one to derive.
  ///
  /// A flat prescribed dose is copied as-is; a per-kilogram rate is resolved
  /// against that bird's newest weight and only when the weight is fresh. Both
  /// stay editable — this is the vet's own arithmetic, not a lock.
  void _seedAmounts() {
    final l10n = context.l10n;
    setState(() {
      for (final due in _dues) {
        final plan = due.medication!;
        final controller = _amounts[plan.id];
        if (controller == null || controller.text.isNotEmpty) continue;
        final rate = plan.doseRate;
        if (rate == null) {
          if (plan.dose != null) {
            controller.text = formatDose(l10n, plan.dose, null);
          }
          continue;
        }
        final weight = _weights[due.caseId];
        final result = calculateDose(
          rate: rate,
          weightG: weight?.weightG,
          weighedAt: weight?.measuredAt ?? weight?.created,
          concentrationPerMl: plan.concentrationPerMl,
        );
        // Not from a stale weight, and not from none: those are exactly the
        // rows where a number would be a guess, so they are left to be typed.
        if (!result.hasAmount ||
            result.warnings.contains(DoseWarning.staleWeight)) {
          continue;
        }
        controller.text = formatDose(l10n, result.amount, null);
        _derivations[plan.id] = result;
      }
    });
  }

  /// The dues still ticked.
  List<WorklistItem> get _selected => [
    for (final due in _dues)
      if (!_excluded.contains(due.medication!.id)) due,
  ];

  double? _amountOf(String medicationId) =>
      double.tryParse(_amounts[medicationId]!.text.trim().replaceAll(',', '.'));

  Future<void> _pickDate() async {
    final picked = await pickDateTime(context, initial: _administeredAt);
    if (picked != null) {
      setState(() => _administeredAt = picked);
      markDirty();
    }
  }

  Future<void> _save() async {
    final chosen = _selected;
    if (chosen.isEmpty) return;
    if (!(formKey.currentState?.validate() ?? false)) return;

    final ok = await runSave(() async {
      final repo = await ref.read(
        medicationAdministrationsRepositoryProvider.future,
      );
      final doses = <Map<String, dynamic>>[];
      for (final due in chosen) {
        final plan = due.medication!;
        final amount = _amountOf(plan.id);
        // The derivation only describes the dose while the number is still the
        // one it produced — the same rule the single-dose sheet applies.
        final derived = _derivations[plan.id];
        final matches = derived != null && derived.amount == amount;
        doses.add({
          'medication': plan.id,
          'dose': amount,
          'weight_g_used': matches ? _weights[due.caseId]?.weightG : null,
          'volume_ml': matches ? derived.volumeMl : null,
        });
      }

      _saved = await repo.administerBatch(
        doses,
        {
          'administered_at': _administeredAt.toUtc().toIso8601String(),
          'notes': trimToNull(_notes) ?? '',
        },
        idempotencyKey: _idempotencyKey,
      );

      for (final due in chosen) {
        ref.invalidate(caseBundleProvider(due.caseId));
      }
      // Each plan's next-due moves on, so the worklist this round came from has
      // to be re-read rather than merely recomputed against the cached source.
      ref.invalidate(worklistSourceProvider);
    });
    if (ok && mounted) Navigator.of(context).pop(_saved);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final chosen = _selected;

    return guardUnsavedChanges(
      child: SheetScaffold(
        title: widget.group.drug.isEmpty
            ? l10n.doseRoundTitle
            : l10n.doseRoundTitleFor(widget.group.drug),
        formKey: formKey,
        onFormChanged: markDirty,
        isBusy: isBusy,
        error: saveError,
        // Nothing selected means the button does nothing rather than
        // disappearing: a disabled control still says the act exists.
        onSave: () {
          if (chosen.isNotEmpty) _save().ignore();
        },
        saveLabel: l10n.doseRoundSaveAction(chosen.length),
        children: [
          Text(
            l10n.doseRoundIntro,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (!_weightsLoaded) ...[
            const SizedBox(height: AppSpacing.sm),
            const LinearProgressIndicator(),
          ],
          if (_weightsFailed) ...[
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
                    l10n.doseRoundWeightsFailed,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          for (final due in _dues)
            _DoseRow(
              due: due,
              controller: _amounts[due.medication!.id]!,
              weight: _weights[due.caseId],
              derivation: _derivations[due.medication!.id],
              selected: !_excluded.contains(due.medication!.id),
              enabled: !isBusy,
              onChanged: (on) {
                setState(() {
                  if (on) {
                    _excluded.remove(due.medication!.id);
                  } else {
                    _excluded.add(due.medication!.id);
                  }
                });
                markDirty();
              },
              // A typed number is the carer's, so the derivation no longer
              // describes it and must not be stored beside it.
              onAmountChanged: () => setState(() {
                final plan = due.medication!;
                final derived = _derivations[plan.id];
                if (derived != null && derived.amount != _amountOf(plan.id)) {
                  _derivations.remove(plan.id);
                }
              }),
            ),
          const SizedBox(height: AppSpacing.md),
          const Divider(),
          const SizedBox(height: AppSpacing.sm),
          DateField(
            label: l10n.doseGivenAt,
            value: _administeredAt,
            enabled: !isBusy,
            showTime: true,
            onPick: _pickDate,
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _notes,
            label: l10n.medNotes,
            enabled: !isBusy,
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
          ),
        ],
      ),
    );
  }
}

/// One bird's row in a dose round: tick to include, and the amount given.
///
/// The amount sits beside the name rather than behind a tap, because it is the
/// one thing that differs per bird and the one thing worth checking.
class _DoseRow extends StatelessWidget {
  const _DoseRow({
    required this.due,
    required this.controller,
    required this.weight,
    required this.derivation,
    required this.selected,
    required this.enabled,
    required this.onChanged,
    required this.onAmountChanged,
  });

  final WorklistItem due;
  final TextEditingController controller;
  final Weight? weight;
  final DoseCalculation? derivation;
  final bool selected;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final VoidCallback onAmountChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final plan = due.medication!;
    final unit = plan.doseUnit ?? '';
    // Why this number: the weight it came from, so a wrong prefill is visible
    // before the syringe rather than in the record afterwards.
    final derived = derivation;
    final w = weight;
    final subtitle = switch ((derived, w)) {
      (final d?, final w?) when d.volumeMl != null =>
        l10n.doseRoundDerivedVolume(
          formatWeightG(l10n, w.weightG),
          formatNumber(l10n, d.volumeMl!),
        ),
      (_?, final w?) => l10n.doseRoundDerivedFrom(
        formatWeightG(l10n, w.weightG),
      ),
      // A rate with no usable weight is the one case that must speak up: the
      // amount is blank BECAUSE nothing could derive it.
      (null, _) when plan.doseRate != null =>
        w == null
            ? l10n.doseRoundNoWeight
            : l10n.doseRoundStaleWeight(
                formatLocalDate(
                  MaterialLocalizations.of(context),
                  w.measuredAt ?? w.created,
                ),
              ),
      _ => null,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: CheckboxListTile(
              value: selected,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                caseTitleLabel(
                  l10n,
                  caseNumber: due.caseNumber,
                  animalName: due.animalName,
                ),
              ),
              subtitle: subtitle == null
                  ? null
                  : Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: derived == null
                            ? theme.colorScheme.error
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
              onChanged: enabled ? (v) => onChanged(v ?? false) : null,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: 112,
            child: AppTextField(
              controller: controller,
              label: l10n.medDose,
              suffixText: unit.isEmpty ? null : unit,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp('[0-9.,]')),
              ],
              enabled: enabled && selected,
              onChanged: (_) => onAmountChanged(),
            ),
          ),
        ],
      ),
    );
  }
}
