import 'package:federfall/features/animals/vaccinations/vaccine_field.dart';
import 'package:federfall/features/cases/cases_labels.dart';
import 'package:federfall/features/cases/medications/medication_routes_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What a vaccination form asks, held in one place so the single-animal sheet
/// and the batch sheet cannot drift apart. One is "this bird got this shot",
/// the other is "these thirty birds got the same shot" — the questions are
/// identical, only the subject differs.
///
/// The state lives here rather than in the widget because the hosts build the
/// request payload from it: [payload] is the shared-field map both the record
/// write and `POST /api/federfall/vaccinate-batch` send.
class VaccinationFormModel {
  VaccinationFormModel({Vaccination? from})
    : vaccine = TextEditingController(text: from?.vaccine ?? ''),
      target = TextEditingController(text: from?.target ?? ''),
      batch = TextEditingController(text: from?.batch ?? ''),
      dose = TextEditingController(text: from?.dose?.toString() ?? ''),
      doseUnit = TextEditingController(text: from?.doseUnit ?? 'ml'),
      vet = TextEditingController(text: from?.vet ?? ''),
      notes = TextEditingController(text: from?.notes ?? ''),
      administeredAt =
          (from?.administeredAt ?? from?.created)?.toLocal() ?? DateTime.now(),
      nextDueAt = from?.nextDueAt?.toLocal(),
      series = from?.series,
      route = from?.route;

  final TextEditingController vaccine;
  final TextEditingController target;
  final TextEditingController batch;
  final TextEditingController dose;
  final TextEditingController doseUnit;
  final TextEditingController vet;
  final TextEditingController notes;

  DateTime administeredAt;
  DateTime? nextDueAt;
  VaccinationSeries? series;
  String? route;

  /// Set once a host has validated an empty product, so the editable dropdown
  /// (not a `Form` field) can show the error the way `SpeciesField` does.
  String? vaccineError;

  String get vaccineText => vaccine.text.trim();

  double? get doseValue =>
      double.tryParse(dose.text.trim().replaceAll(',', '.'));

  /// The shared fields as PocketBase sends them. [clearing] fills every key
  /// even when empty, which is what an UPDATE needs to actually clear a field;
  /// a CREATE and the batch route omit the empties instead.
  Map<String, dynamic> payload({bool clearing = false}) {
    final target_ = target.text.trim();
    final batch_ = batch.text.trim();
    final vet_ = vet.text.trim();
    final notes_ = notes.text.trim();
    final unit = doseUnit.text.trim();
    final due = nextDueAt?.toUtc().toIso8601String();

    if (clearing) {
      return {
        'vaccine': vaccineText,
        'target': target_,
        'administered_at': administeredAt.toUtc().toIso8601String(),
        'batch': batch_,
        // Empty clears the value; PocketBase stores 0 for a null number, and
        // the model reads that back as "no dose" (pbQuantity).
        'dose': doseValue ?? 0,
        'dose_unit': unit,
        'route': route ?? '',
        'series': series?.wire ?? '',
        'next_due_at': due ?? '',
        'vet': vet_,
        'notes': notes_,
      };
    }
    return {
      'vaccine': vaccineText,
      'target': ?(target_.isEmpty ? null : target_),
      'administered_at': administeredAt.toUtc().toIso8601String(),
      'batch': ?(batch_.isEmpty ? null : batch_),
      'dose': ?doseValue,
      'dose_unit': ?(unit.isEmpty ? null : unit),
      'route': ?route,
      'series': ?series?.wire,
      'next_due_at': ?due,
      'vet': ?(vet_.isEmpty ? null : vet_),
      'notes': ?(notes_.isEmpty ? null : notes_),
    };
  }

  void dispose() {
    vaccine.dispose();
    target.dispose();
    batch.dispose();
    dose.dispose();
    doseUnit.dispose();
    vet.dispose();
    notes.dispose();
  }
}

/// The field set itself. [onChanged] fires for anything the host has to treat
/// as a dirty edit; the text controllers are watched by the enclosing `Form`.
class VaccinationFields extends ConsumerStatefulWidget {
  const VaccinationFields({
    required this.model,
    required this.enabled,
    required this.onChanged,
    super.key,
  });

  final VaccinationFormModel model;
  final bool enabled;
  final VoidCallback onChanged;

  @override
  ConsumerState<VaccinationFields> createState() => _VaccinationFieldsState();
}

class _VaccinationFieldsState extends ConsumerState<VaccinationFields> {
  VaccinationFormModel get _model => widget.model;

  /// Picking a product fills in the target it was last recorded against — but
  /// only into an EMPTY field, so it never overwrites what somebody typed.
  void _onVaccinePicked(String vaccine) {
    if (_model.target.text.trim().isNotEmpty) return;
    final target = targetForVaccine(ref, vaccine);
    if (target != null) {
      setState(() => _model.target.text = target);
      widget.onChanged();
    }
  }

  Future<void> _pickAdministeredAt() async {
    final picked = await pickDate(context, initial: _model.administeredAt);
    if (picked != null) {
      setState(() => _model.administeredAt = picked);
      widget.onChanged();
    }
  }

  Future<void> _pickNextDue() async {
    final picked = await pickDate(
      context,
      initial:
          _model.nextDueAt ??
          _model.administeredAt.add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _model.nextDueAt = picked);
      widget.onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final enabled = widget.enabled;
    final routes = (ref.watch(medicationRoutesProvider).value ?? const [])
        .where((r) => r.active || r.id == _model.route)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DateField(
          label: l10n.vaccinationFieldDate,
          value: _model.administeredAt,
          enabled: enabled,
          onPick: _pickAdministeredAt,
        ),
        const SizedBox(height: AppSpacing.md),
        VaccineSuggestionField(
          controller: _model.vaccine,
          label: l10n.vaccinationFieldVaccine,
          icon: Icons.vaccines_outlined,
          options: vaccineOptions(ref),
          enabled: enabled,
          errorText: _model.vaccineError,
          onSelected: _onVaccinePicked,
        ),
        const SizedBox(height: AppSpacing.md),
        VaccineSuggestionField(
          controller: _model.target,
          label: l10n.vaccinationFieldTarget,
          icon: Icons.shield_outlined,
          options: targetOptions(ref),
          enabled: enabled,
        ),
        const SizedBox(height: AppSpacing.md),
        AppTextField(
          controller: _model.batch,
          label: l10n.vaccinationFieldBatch,
          hintText: l10n.vaccinationFieldBatchHint,
          enabled: enabled,
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AppTextField(
                controller: _model.dose,
                label: l10n.vaccinationFieldDose,
                enabled: enabled,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (v) {
                  final raw = (v ?? '').trim();
                  if (raw.isEmpty) return null;
                  final n = double.tryParse(raw.replaceAll(',', '.'));
                  return (n == null || n <= 0) ? l10n.fieldRequired : null;
                },
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            SizedBox(
              width: 96,
              child: AppTextField(
                controller: _model.doseUnit,
                label: l10n.medUnit,
                enabled: enabled,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<String?>(
          initialValue: _model.route,
          decoration: InputDecoration(
            labelText: l10n.medRoute,
            prefixIcon: const Icon(Icons.alt_route_outlined),
          ),
          items: [
            DropdownMenuItem(child: Text(l10n.fieldNotSpecified)),
            for (final r in routes)
              DropdownMenuItem(value: r.id, child: Text(r.label)),
          ],
          onChanged: enabled
              ? (r) {
                  setState(() => _model.route = r);
                  widget.onChanged();
                }
              : null,
        ),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<VaccinationSeries?>(
          initialValue: _model.series,
          decoration: InputDecoration(
            labelText: l10n.vaccinationFieldSeries,
            prefixIcon: const Icon(Icons.repeat_outlined),
          ),
          items: [
            DropdownMenuItem(child: Text(l10n.fieldNotSpecified)),
            for (final s in VaccinationSeries.values)
              DropdownMenuItem(
                value: s,
                child: Text(vaccinationSeriesLabel(l10n, s)),
              ),
          ],
          onChanged: enabled
              ? (s) {
                  setState(() => _model.series = s);
                  widget.onChanged();
                }
              : null,
        ),
        const SizedBox(height: AppSpacing.md),
        DateField(
          label: l10n.vaccinationFieldNextDue,
          value: _model.nextDueAt,
          placeholder: l10n.fieldNotSpecified,
          enabled: enabled,
          onPick: _pickNextDue,
          onClear: _model.nextDueAt == null
              ? null
              : () {
                  setState(() => _model.nextDueAt = null);
                  widget.onChanged();
                },
        ),
        const SizedBox(height: AppSpacing.md),
        AppTextField(
          controller: _model.vet,
          label: l10n.vaccinationFieldVet,
          hintText: l10n.vaccinationFieldVetHint,
          enabled: enabled,
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: AppSpacing.md),
        AppTextField(
          controller: _model.notes,
          label: l10n.vaccinationFieldNotes,
          enabled: enabled,
          minLines: 2,
          maxLines: 5,
          textCapitalization: TextCapitalization.sentences,
        ),
      ],
    );
  }
}
