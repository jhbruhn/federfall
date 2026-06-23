import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/cases_labels.dart';
import 'package:federfall/features/cases/medications/medications_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_data/federfall_data.dart';
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
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
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

class _PrescriptionSheetState extends ConsumerState<PrescriptionSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _drug;
  late final TextEditingController _dose;
  late final TextEditingController _unit;
  late final TextEditingController _frequency;
  late final TextEditingController _instructions;
  late final TextEditingController _prescribedBy;
  MedicationRoute? _route;
  late DateTime _startedAt;
  DateTime? _endedAt;
  bool _controlled = false;
  bool _busy = false;
  String? _error;

  bool get _isEditing => widget.plan != null;

  @override
  void initState() {
    super.initState();
    final p = widget.plan;
    _drug = TextEditingController(text: p?.drug ?? '');
    _dose = TextEditingController(
      text: p?.dose == null ? '' : formatDose(p!.dose, null),
    );
    _unit = TextEditingController(text: p?.doseUnit ?? '');
    _frequency = TextEditingController(text: p?.frequency ?? '');
    _instructions = TextEditingController(text: p?.instructions ?? '');
    _prescribedBy = TextEditingController(text: p?.prescribedBy ?? '');
    _route = p?.route;
    _startedAt = p?.startedAt ?? p?.created ?? DateTime.now();
    _endedAt = p?.endedAt;
    _controlled = p?.isControlled ?? false;
  }

  @override
  void dispose() {
    for (final c in [
      _drug,
      _dose,
      _unit,
      _frequency,
      _instructions,
      _prescribedBy,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _trim(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
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
      final repo = await ref.read(medicationsRepositoryProvider.future);
      final dose = double.tryParse(_dose.text.trim().replaceAll(',', '.'));

      final body = <String, dynamic>{
        'drug': _drug.text.trim(),
        'dose': dose,
        'dose_unit': _trim(_unit) ?? '',
        'frequency': _trim(_frequency) ?? '',
        'route': _route?.wire ?? '',
        'started_at': _startedAt.toUtc().toIso8601String(),
        'ended_at': _endedAt?.toUtc().toIso8601String() ?? '',
        'is_controlled': _controlled,
        'instructions': _trim(_instructions) ?? '',
        'prescribed_by': _trim(_prescribedBy) ?? '',
      };

      final plan = widget.plan;
      if (plan == null) {
        await repo.create({...body, 'case': widget.caseId, 'org': org});
      } else {
        await repo.update(plan.id, body);
      }

      ref.invalidate(medicationsForCaseProvider(widget.caseId));
      if (mounted) Navigator.of(context).pop(true);
    } on RepositoryException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = errorMessage(l10n, e);
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = l10n.errorGenericTitle;
      });
    }
  }

  Future<void> _pickStarted() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startedAt,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _startedAt = picked);
  }

  Future<void> _pickEnded() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endedAt ?? _startedAt,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _endedAt = picked);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg + viewInsets,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _isEditing
                    ? l10n.prescriptionEditTitle
                    : l10n.prescriptionNewTitle,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                controller: _drug,
                label: l10n.medDrug,
                prefixIcon: Icons.medication_outlined,
                enabled: !_busy,
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
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp('[0-9.,]')),
                      ],
                      enabled: !_busy,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: AppTextField(
                      controller: _unit,
                      label: l10n.medUnit,
                      enabled: !_busy,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              MedicationRouteDropdown(
                value: _route,
                enabled: !_busy,
                onChanged: (r) => setState(() => _route = r),
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                controller: _frequency,
                label: l10n.medFrequency,
                hintText: l10n.medFrequencyHint,
                prefixIcon: Icons.repeat,
                enabled: !_busy,
              ),
              const SizedBox(height: AppSpacing.md),
              DateField(
                label: l10n.medStarted,
                value: _startedAt,
                enabled: !_busy,
                onPick: _pickStarted,
              ),
              const SizedBox(height: AppSpacing.md),
              DateField(
                label: l10n.medEnded,
                value: _endedAt,
                enabled: !_busy,
                onPick: _pickEnded,
                onClear: () => setState(() => _endedAt = null),
                placeholder: l10n.caseDateNotSet,
              ),
              const SizedBox(height: AppSpacing.sm),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.medControlled),
                value: _controlled,
                onChanged:
                    _busy ? null : (v) => setState(() => _controlled = v),
              ),
              AppTextField(
                controller: _instructions,
                label: l10n.medInstructions,
                prefixIcon: Icons.notes_outlined,
                enabled: !_busy,
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                controller: _prescribedBy,
                label: l10n.medPrescribedBy,
                prefixIcon: Icons.local_hospital_outlined,
                enabled: !_busy,
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _error!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error),
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
    );
  }
}

/// Optional route picker shared by the prescription and dose forms.
class MedicationRouteDropdown extends StatelessWidget {
  const MedicationRouteDropdown({
    required this.value,
    required this.enabled,
    required this.onChanged,
    super.key,
  });

  final MedicationRoute? value;
  final bool enabled;
  final ValueChanged<MedicationRoute?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return DropdownButtonFormField<MedicationRoute>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: l10n.medRoute,
        prefixIcon: const Icon(Icons.vaccines_outlined),
      ),
      items: [
        for (final r in MedicationRoute.values)
          DropdownMenuItem(
            value: r,
            child: Text(medicationRouteLabel(l10n, r)),
          ),
      ],
      onChanged: enabled ? onChanged : null,
    );
  }
}
