import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/features/cases/medications/medications_providers.dart';
import 'package:federfall/features/cases/medications/prescription_sheet.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
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
  return showAppSheet<bool>(
    context,
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

class _AdministrationSheetState extends ConsumerState<AdministrationSheet>
    with DiscardGuard, FormSheetState {
  late final TextEditingController _drug;
  late final TextEditingController _dose;
  late final TextEditingController _unit;
  late final TextEditingController _notes;
  String? _route;
  late DateTime _administeredAt;

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
    _administeredAt = a?.administeredAt?.toLocal() ?? DateTime.now();
  }

  @override
  void dispose() {
    for (final c in [_drug, _dose, _unit, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await pickDateTime(context, initial: _administeredAt);
    if (picked != null) {
      setState(() => _administeredAt = picked);
      markDirty();
    }
  }

  Future<void> _save() async {
    if (!(formKey.currentState?.validate() ?? false)) return;

    final ok = await runSave(() async {
      final (user, org) = await requireUserOrg();
      final repo = await ref.read(
        medicationAdministrationsRepositoryProvider.future,
      );
      final dose = double.tryParse(_dose.text.trim().replaceAll(',', '.'));
      final administration = widget.administration;

      final body = <String, dynamic>{
        'drug': _drug.text.trim(),
        'dose': dose,
        'dose_unit': trimToNull(_unit) ?? '',
        'route': _route ?? '',
        'administered_at': _administeredAt.toUtc().toIso8601String(),
        'notes': trimToNull(_notes) ?? '',
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

      ref.invalidate(caseBundleProvider(widget.caseId));
    });
    if (ok && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return guardUnsavedChanges(
      child: SheetScaffold(
        title: _isEditing ? l10n.doseEditTitle : l10n.doseNewTitle,
        formKey: formKey,
        onFormChanged: markDirty,
        isBusy: isBusy,
        error: saveError,
        onSave: _save,
        children: [
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
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp('[0-9.,]')),
                  ],
                  enabled: !isBusy,
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
          const SizedBox(height: AppSpacing.md),
          MedicationRouteDropdown(
            value: _route,
            enabled: !isBusy,
            onChanged: (r) {
              setState(() => _route = r);
              markDirty();
            },
          ),
          const SizedBox(height: AppSpacing.md),
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
