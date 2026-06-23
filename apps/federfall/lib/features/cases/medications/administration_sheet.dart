import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/medications/medications_providers.dart';
import 'package:federfall/features/cases/medications/prescription_sheet.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the dose-administration add/edit form. Pass [plan] to pre-fill from a
/// prescription (and link the dose to it); pass [administration] to edit.
Future<bool?> showAdministrationSheet(
  BuildContext context, {
  required String caseId,
  Medication? plan,
  MedicationAdministration? administration,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => AdministrationSheet(
      caseId: caseId,
      plan: plan,
      administration: administration,
    ),
  );
}

/// Form for logging a single dose given (FED-4.6). Pre-fills drug/dose/route
/// from a [plan] when present and links the dose to it; otherwise it is an
/// ad-hoc dose. The administering carer and time default to now.
class AdministrationSheet extends ConsumerStatefulWidget {
  const AdministrationSheet({
    required this.caseId,
    this.plan,
    this.administration,
    super.key,
  });

  final String caseId;
  final Medication? plan;
  final MedicationAdministration? administration;

  @override
  ConsumerState<AdministrationSheet> createState() =>
      _AdministrationSheetState();
}

class _AdministrationSheetState extends ConsumerState<AdministrationSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _drug;
  late final TextEditingController _dose;
  late final TextEditingController _unit;
  late final TextEditingController _notes;
  MedicationRoute? _route;
  late DateTime _administeredAt;
  bool _busy = false;
  String? _error;

  bool get _isEditing => widget.administration != null;

  @override
  void initState() {
    super.initState();
    final a = widget.administration;
    final p = widget.plan;
    _drug = TextEditingController(text: a?.drug ?? p?.drug ?? '');
    _dose = TextEditingController(
      text: (a?.dose ?? p?.dose) == null
          ? ''
          : formatDose(a?.dose ?? p?.dose, null),
    );
    _unit = TextEditingController(text: a?.doseUnit ?? p?.doseUnit ?? '');
    _notes = TextEditingController(text: a?.notes ?? '');
    _route = a?.route ?? p?.route;
    _administeredAt = a?.administeredAt ?? DateTime.now();
  }

  @override
  void dispose() {
    for (final c in [_drug, _dose, _unit, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _trim(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _administeredAt,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _administeredAt = picked);
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
      final repo =
          await ref.read(medicationAdministrationsRepositoryProvider.future);
      final dose = double.tryParse(_dose.text.trim().replaceAll(',', '.'));
      final administration = widget.administration;

      final body = <String, dynamic>{
        'drug': _drug.text.trim(),
        'dose': dose,
        'dose_unit': _trim(_unit) ?? '',
        'route': _route?.wire ?? '',
        'administered_at': _administeredAt.toUtc().toIso8601String(),
        'notes': _trim(_notes) ?? '',
      };

      if (administration == null) {
        await repo.create({
          ...body,
          'case': widget.caseId,
          'medication': ?widget.plan?.id,
          'administered_by': user.id,
          'org': org,
        });
      } else {
        await repo.update(administration.id, body);
      }

      ref.invalidate(administrationsForCaseProvider(widget.caseId));
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
                _isEditing ? l10n.doseEditTitle : l10n.doseNewTitle,
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
              DateField(
                label: l10n.doseGivenAt,
                value: _administeredAt,
                enabled: !_busy,
                onPick: _pickDate,
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                controller: _notes,
                label: l10n.medNotes,
                prefixIcon: Icons.notes_outlined,
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
