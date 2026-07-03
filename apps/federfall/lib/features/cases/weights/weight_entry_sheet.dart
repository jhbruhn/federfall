import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/features/cases/weights/weights_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the weight add/edit form as a modal bottom sheet. Pass [weight] to
/// edit an existing measurement; omit it to add one. Resolves to `true` on
/// save.
Future<bool?> showWeightEntrySheet(
  BuildContext context, {
  required String animalId,
  String? caseId,
  Weight? weight,
}) {
  return showAppSheet<bool>(
    context,
    builder: (_) =>
        WeightEntrySheet(animalId: animalId, caseId: caseId, weight: weight),
  );
}

/// Form for recording or editing a weight measurement (FED-4.4): the weight in
/// grams, the measurement date and an optional note. Weights belong to the
/// animal; [caseId] records the treatment episode when taken during one.
class WeightEntrySheet extends ConsumerStatefulWidget {
  const WeightEntrySheet({
    required this.animalId,
    this.caseId,
    this.weight,
    super.key,
  });

  final String animalId;
  final String? caseId;
  final Weight? weight;

  @override
  ConsumerState<WeightEntrySheet> createState() => _WeightEntrySheetState();
}

class _WeightEntrySheetState extends ConsumerState<WeightEntrySheet>
    with DiscardGuard, FormSheetState {
  late final TextEditingController _weightController;
  late final TextEditingController _notesController;
  late DateTime _measuredAt;

  bool get _isEditing => widget.weight != null;

  @override
  void initState() {
    super.initState();
    final w = widget.weight;
    _weightController = TextEditingController(
      text: w == null ? '' : formatGramsInput(w.weightG),
    );
    _notesController = TextEditingController(text: w?.notes ?? '');
    _measuredAt = (w?.measuredAt ?? w?.created)?.toLocal() ?? DateTime.now();
  }

  @override
  void dispose() {
    _weightController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  /// Parses the grams field, accepting both `,` and `.` as the decimal mark.
  double? _parseGrams() =>
      double.tryParse(_weightController.text.trim().replaceAll(',', '.'));

  String? _validateGrams(String? _) {
    final l10n = context.l10n;
    final grams = _parseGrams();
    if (grams == null) return l10n.fieldRequired;
    if (grams <= 0) return l10n.weightFieldInvalid;
    return null;
  }

  Future<void> _pickDate() async {
    final picked = await pickDate(context, initial: _measuredAt);
    if (picked != null) {
      setState(() => _measuredAt = picked);
      markDirty();
    }
  }

  Future<void> _save() async {
    if (!(formKey.currentState?.validate() ?? false)) return;

    final ok = await runSave(() async {
      final (user, org) = await requireUserOrg();
      final repo = await ref.read(weightsRepositoryProvider.future);
      final grams = _parseGrams();
      final notes = _notesController.text.trim();
      final notesOrNull = notes.isEmpty ? null : notes;
      final weight = widget.weight;

      if (weight == null) {
        await repo.create({
          'animal': widget.animalId,
          'case': ?widget.caseId,
          'weight_g': grams,
          'measured_at': _measuredAt.toUtc().toIso8601String(),
          'notes': ?notesOrNull,
          'author': user.id,
          'org': org,
        });
      } else {
        await repo.update(weight.id, {
          'weight_g': grams,
          'measured_at': _measuredAt.toUtc().toIso8601String(),
          'notes': notes,
        });
      }

      ref.invalidate(weightsForAnimalProvider(widget.animalId));
      if (widget.caseId case final caseId?) {
        ref.invalidate(caseBundleProvider(caseId));
      }
    });
    if (ok && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return guardUnsavedChanges(
      child: SheetScaffold(
        title: _isEditing ? l10n.weightEditTitle : l10n.weightNewTitle,
        formKey: formKey,
        onFormChanged: markDirty,
        isBusy: isBusy,
        error: saveError,
        onSave: _save,
        children: [
          AppTextField(
            controller: _weightController,
            label: l10n.weightFieldGrams,
            prefixIcon: Icons.monitor_weight_outlined,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp('[0-9.,]')),
            ],
            enabled: !isBusy,
            validator: _validateGrams,
          ),
          const SizedBox(height: AppSpacing.md),
          DateField(
            label: l10n.weightFieldDate,
            value: _measuredAt,
            enabled: !isBusy,
            onPick: _pickDate,
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _notesController,
            label: l10n.weightFieldNotes,
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

/// Pre-fills the grams field without a forced decimal (e.g. `248`, `248.5`).
String formatGramsInput(double grams) => grams == grams.roundToDouble()
    ? grams.toStringAsFixed(0)
    : grams.toString();
