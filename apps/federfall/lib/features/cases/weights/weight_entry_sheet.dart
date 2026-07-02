import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/weights/weights_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_data/federfall_data.dart';
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
    with DiscardGuard {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _weightController;
  late final TextEditingController _notesController;
  late DateTime _measuredAt;
  bool _busy = false;
  String? _error;

  bool get _isEditing => widget.weight != null;

  @override
  void initState() {
    super.initState();
    final w = widget.weight;
    _weightController = TextEditingController(
      text: w == null ? '' : formatGramsInput(w.weightG),
    );
    _notesController = TextEditingController(text: w?.notes ?? '');
    _measuredAt = w?.measuredAt ?? w?.created ?? DateTime.now();
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
    final picked = await showDatePicker(
      context: context,
      initialDate: _measuredAt,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _measuredAt = picked);
      markDirty();
    }
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final user = await ref.read(currentUserProvider.future);
      final org = user?.org;
      if (user == null || org == null) {
        throw const RepositoryException('no org for current user');
      }

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
      if (widget.caseId != null) {
        ref.invalidate(weightsForCaseProvider(widget.caseId!));
      }
      if (mounted) Navigator.of(context).pop(true);
    } on RepositoryException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = errorMessage(l10n, e);
      });
    } on Object catch (error, stackTrace) {
      reportCaughtError(error, stackTrace);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = l10n.errorGenericTitle;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    final materialL10n = MaterialLocalizations.of(context);

    return guardUnsavedChanges(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg + viewInsets,
        ),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            onChanged: markDirty,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _isEditing ? l10n.weightEditTitle : l10n.weightNewTitle,
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  controller: _weightController,
                  label: l10n.weightFieldGrams,
                  prefixIcon: Icons.monitor_weight_outlined,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp('[0-9.,]')),
                  ],
                  enabled: !_busy,
                  validator: _validateGrams,
                ),
                const SizedBox(height: AppSpacing.md),
                InkWell(
                  onTap: _busy ? null : _pickDate,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: l10n.weightFieldDate,
                      prefixIcon: const Icon(Icons.event_outlined),
                    ),
                    child: Text(materialL10n.formatMediumDate(_measuredAt)),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  controller: _notesController,
                  label: l10n.weightFieldNotes,
                  enabled: !_busy,
                  minLines: 2,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                PrimaryButton(
                  label: l10n.actionSave,
                  icon: Icons.check,
                  isLoading: _busy,
                  onPressed: _save,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pre-fills the grams field without a forced decimal (e.g. `248`, `248.5`).
String formatGramsInput(double grams) => grams == grams.roundToDouble()
    ? grams.toStringAsFixed(0)
    : grams.toString();
