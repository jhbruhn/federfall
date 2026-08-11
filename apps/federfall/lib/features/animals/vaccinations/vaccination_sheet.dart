import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/animals/vaccinations/vaccinations_providers.dart';
import 'package:federfall/features/animals/vaccinations/vaccine_field.dart';
import 'package:federfall/features/cases/cases_labels.dart';
import 'package:federfall/features/cases/journal/journal_providers.dart';
import 'package:federfall/features/cases/medications/medication_routes_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

/// Opens the vaccination form as a modal bottom sheet. Pass [vaccination] to
/// edit an existing record; omit it to record a new one. Resolves to `true` on
/// save.
///
/// There is no `caseId` parameter anywhere in this feature: a shot belongs to
/// the animal, and the case timelines it appears on are derived from its date
/// (see [vaccinationsForCase]).
Future<bool?> showVaccinationSheet(
  BuildContext context, {
  required String animalId,
  Vaccination? vaccination,
}) {
  return showAppSheet<bool>(
    context,
    builder: (_) =>
        VaccinationSheet(animalId: animalId, vaccination: vaccination),
  );
}

/// Form for recording or editing one vaccination (1700000087): the date, the
/// product and what it protects against, the batch number, dose and route,
/// whether it was a primary course or a booster, when the next one is due, who
/// gave it, a note and up to three images.
class VaccinationSheet extends ConsumerStatefulWidget {
  const VaccinationSheet({
    required this.animalId,
    this.vaccination,
    super.key,
  });

  final String animalId;
  final Vaccination? vaccination;

  /// PocketBase caps `vaccinations.attachments` at three files (1700000087).
  static const int maxAttachments = 3;

  @override
  ConsumerState<VaccinationSheet> createState() => _VaccinationSheetState();
}

class _VaccinationSheetState extends ConsumerState<VaccinationSheet>
    with DiscardGuard, FormSheetState {
  late final TextEditingController _vaccineController;
  late final TextEditingController _targetController;
  late final TextEditingController _batchController;
  late final TextEditingController _doseController;
  late final TextEditingController _doseUnitController;
  late final TextEditingController _vetController;
  late final TextEditingController _notesController;
  late DateTime _administeredAt;
  DateTime? _nextDueAt;
  VaccinationSeries? _series;
  String? _route;

  /// Set once the host has validated an empty product, so the editable dropdown
  /// (not a `Form` field) can show the error the way `SpeciesField` does.
  String? _vaccineError;

  late final List<String> _existingAttachments;
  final _newAttachments = <XFile>[];

  bool get _isEditing => widget.vaccination != null;

  int get _attachmentCount =>
      _existingAttachments.length + _newAttachments.length;

  int get _slotsLeft => VaccinationSheet.maxAttachments - _attachmentCount;

  @override
  void initState() {
    super.initState();
    final v = widget.vaccination;
    _vaccineController = TextEditingController(text: v?.vaccine ?? '');
    _targetController = TextEditingController(text: v?.target ?? '');
    _batchController = TextEditingController(text: v?.batch ?? '');
    _doseController = TextEditingController(text: v?.dose?.toString() ?? '');
    _doseUnitController = TextEditingController(text: v?.doseUnit ?? 'ml');
    _vetController = TextEditingController(text: v?.vet ?? '');
    _notesController = TextEditingController(text: v?.notes ?? '');
    _administeredAt =
        (v?.administeredAt ?? v?.created)?.toLocal() ?? DateTime.now();
    _nextDueAt = v?.nextDueAt?.toLocal();
    _series = v?.series;
    _route = v?.route;
    _existingAttachments = [...?v?.attachments];
  }

  @override
  void dispose() {
    _vaccineController.dispose();
    _targetController.dispose();
    _batchController.dispose();
    _doseController.dispose();
    _doseUnitController.dispose();
    _vetController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  /// Picking a product fills in the target it was last recorded against — but
  /// only into an EMPTY field, so it never overwrites what somebody typed.
  void _onVaccinePicked(String vaccine) {
    if (_targetController.text.trim().isNotEmpty) return;
    final target = targetForVaccine(ref, vaccine);
    if (target != null) {
      setState(() => _targetController.text = target);
      markDirty();
    }
  }

  Future<void> _pickAdministeredAt() async {
    final picked = await pickDate(context, initial: _administeredAt);
    if (picked != null) {
      setState(() => _administeredAt = picked);
      markDirty();
    }
  }

  Future<void> _pickNextDue() async {
    final picked = await pickDate(
      context,
      initial: _nextDueAt ?? _administeredAt.add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _nextDueAt = picked);
      markDirty();
    }
  }

  Future<void> _pickImages() async {
    final picker = ref.read(imagePickerProvider);
    final picked = await picker.pickMultiImage();
    if (picked.isNotEmpty) {
      // The server rejects a fourth file outright, so cap the selection here
      // rather than let the save fail after the upload.
      setState(() => _newAttachments.addAll(picked.take(_slotsLeft)));
      markDirty();
    }
  }

  Future<void> _takePhoto() async {
    final picker = ref.read(imagePickerProvider);
    final shot = await picker.pickImage(source: ImageSource.camera);
    if (shot != null) {
      setState(() => _newAttachments.add(shot));
      markDirty();
    }
  }

  Future<List<http.MultipartFile>> _multipart() async {
    final files = <http.MultipartFile>[];
    for (final file in _newAttachments) {
      files.add(
        http.MultipartFile.fromBytes(
          'attachments',
          await file.readAsBytes(),
          filename: file.name,
        ),
      );
    }
    return files;
  }

  Uri Function(String)? _thumbUrl() {
    final repo = ref.watch(vaccinationsRepositoryProvider).value;
    final id = widget.vaccination?.id;
    if (repo == null || id == null) return null;
    return (filename) => repo.fileUrl(id, filename, thumb: '200x200');
  }

  Future<void> _save() async {
    final vaccine = _vaccineController.text.trim();
    // The product is required server-side, and the editable dropdown is not a
    // Form field — so it is validated here, like the species field is.
    setState(
      () => _vaccineError = vaccine.isEmpty ? context.l10n.fieldRequired : null,
    );
    if (vaccine.isEmpty) return;
    if (!(formKey.currentState?.validate() ?? false)) return;

    final ok = await runSave(() async {
      final (user, org) = await requireUserOrg();
      final repo = await ref.read(vaccinationsRepositoryProvider.future);
      final files = await _multipart();
      final target = _targetController.text.trim();
      final batch = _batchController.text.trim();
      final vet = _vetController.text.trim();
      final notes = _notesController.text.trim();
      final unit = _doseUnitController.text.trim();
      final dose = double.tryParse(
        _doseController.text.trim().replaceAll(',', '.'),
      );
      final v = widget.vaccination;

      if (v == null) {
        await repo.createWithFiles({
          'animal': widget.animalId,
          'vaccine': vaccine,
          'target': ?(target.isEmpty ? null : target),
          'administered_at': _administeredAt.toUtc().toIso8601String(),
          'batch': ?(batch.isEmpty ? null : batch),
          'dose': ?dose,
          'dose_unit': ?(unit.isEmpty ? null : unit),
          'route': ?_route,
          'series': ?_series?.wire,
          'next_due_at': ?_nextDueAt?.toUtc().toIso8601String(),
          'vet': ?(vet.isEmpty ? null : vet),
          'notes': ?(notes.isEmpty ? null : notes),
          'author': user.id,
          'org': org,
        }, files);
      } else {
        // Never `animal` — it is frozen server-side (1700000087) — and never
        // `org`. A shot recorded on the wrong bird is deleted and re-entered.
        await repo.updateWithFiles(v.id, {
          'vaccine': vaccine,
          'target': target,
          'administered_at': _administeredAt.toUtc().toIso8601String(),
          'batch': batch,
          // Empty clears the value; PocketBase stores 0 for a null number, and
          // the model reads that back as "no dose" (pbQuantity).
          'dose': dose ?? 0,
          'dose_unit': unit,
          'route': _route ?? '',
          'series': _series?.wire ?? '',
          'next_due_at': _nextDueAt?.toUtc().toIso8601String() ?? '',
          'vet': vet,
          'notes': notes,
          // Setting the field to the survivors drops any removed file; the new
          // uploads are appended on top.
          'attachments': _existingAttachments,
        }, files);
      }

      ref
        ..invalidate(vaccinationsForAnimalProvider(widget.animalId))
        // The suggestion view is derived from the rows themselves, so a new
        // product has to become suggestable straight away.
        ..invalidate(vaccineLabelsProvider);
    });
    if (ok && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final routes = (ref.watch(medicationRoutesProvider).value ?? const [])
        .where((r) => r.active || r.id == _route)
        .toList();

    return guardUnsavedChanges(
      child: SheetScaffold(
        title: _isEditing
            ? l10n.vaccinationEditTitle
            : l10n.vaccinationNewTitle,
        formKey: formKey,
        onFormChanged: markDirty,
        isBusy: isBusy,
        error: saveError,
        onSave: _save,
        children: [
          DateField(
            label: l10n.vaccinationFieldDate,
            value: _administeredAt,
            enabled: !isBusy,
            onPick: _pickAdministeredAt,
          ),
          const SizedBox(height: AppSpacing.md),
          VaccineSuggestionField(
            controller: _vaccineController,
            label: l10n.vaccinationFieldVaccine,
            icon: Icons.vaccines_outlined,
            options: vaccineOptions(ref),
            enabled: !isBusy,
            errorText: _vaccineError,
            onSelected: _onVaccinePicked,
          ),
          const SizedBox(height: AppSpacing.md),
          VaccineSuggestionField(
            controller: _targetController,
            label: l10n.vaccinationFieldTarget,
            icon: Icons.shield_outlined,
            options: targetOptions(ref),
            enabled: !isBusy,
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _batchController,
            label: l10n.vaccinationFieldBatch,
            hintText: l10n.vaccinationFieldBatchHint,
            enabled: !isBusy,
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AppTextField(
                  controller: _doseController,
                  label: l10n.vaccinationFieldDose,
                  enabled: !isBusy,
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
                  controller: _doseUnitController,
                  label: l10n.medUnit,
                  enabled: !isBusy,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          DropdownButtonFormField<String?>(
            initialValue: _route,
            decoration: InputDecoration(
              labelText: l10n.medRoute,
              prefixIcon: const Icon(Icons.alt_route_outlined),
            ),
            items: [
              DropdownMenuItem(child: Text(l10n.fieldNotSpecified)),
              for (final r in routes)
                DropdownMenuItem(value: r.id, child: Text(r.label)),
            ],
            onChanged: isBusy ? null : (r) => setState(() => _route = r),
          ),
          const SizedBox(height: AppSpacing.md),
          DropdownButtonFormField<VaccinationSeries?>(
            initialValue: _series,
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
            onChanged: isBusy ? null : (s) => setState(() => _series = s),
          ),
          const SizedBox(height: AppSpacing.md),
          DateField(
            label: l10n.vaccinationFieldNextDue,
            value: _nextDueAt,
            placeholder: l10n.fieldNotSpecified,
            enabled: !isBusy,
            onPick: _pickNextDue,
            onClear: _nextDueAt == null
                ? null
                : () {
                    setState(() => _nextDueAt = null);
                    markDirty();
                  },
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _vetController,
            label: l10n.vaccinationFieldVet,
            hintText: l10n.vaccinationFieldVetHint,
            enabled: !isBusy,
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            l10n.vaccinationAttachmentsLabel,
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: AppSpacing.xs),
          if (_attachmentCount > 0)
            EditablePhotoStrip(
              existing: _existingAttachments,
              newPhotos: _newAttachments,
              thumbUrl: _thumbUrl(),
              onRemoveExisting: isBusy
                  ? null
                  : (i) {
                      setState(() => _existingAttachments.removeAt(i));
                      markDirty();
                    },
              onRemoveNew: isBusy
                  ? null
                  : (i) {
                      setState(() => _newAttachments.removeAt(i));
                      markDirty();
                    },
            ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              OutlinedButton.icon(
                onPressed: isBusy || _slotsLeft == 0 ? null : _pickImages,
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(l10n.vaccinationAddImage),
              ),
              OutlinedButton.icon(
                onPressed: isBusy || _slotsLeft == 0 ? null : _takePhoto,
                icon: const Icon(Icons.photo_camera_outlined),
                label: Text(l10n.vaccinationTakePhoto),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _notesController,
            label: l10n.vaccinationFieldNotes,
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
