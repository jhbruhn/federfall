import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/animals/vaccinations/vaccination_form_fields.dart';
import 'package:federfall/features/animals/vaccinations/vaccinations_providers.dart';
import 'package:federfall/features/cases/journal/journal_providers.dart';
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

/// Form for recording or editing ONE vaccination (1700000087). The fields
/// themselves are [VaccinationFields], shared with the batch sheet; what this
/// adds is the attachments (a vial label, a paper Impfausweis) and the
/// single-record write.
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
  late final VaccinationFormModel _model;
  late final List<String> _existingAttachments;
  final _newAttachments = <XFile>[];

  bool get _isEditing => widget.vaccination != null;

  int get _attachmentCount =>
      _existingAttachments.length + _newAttachments.length;

  int get _slotsLeft => VaccinationSheet.maxAttachments - _attachmentCount;

  @override
  void initState() {
    super.initState();
    _model = VaccinationFormModel(from: widget.vaccination);
    _existingAttachments = [...?widget.vaccination?.attachments];
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
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
    // The product is required server-side, and the editable dropdown is not a
    // Form field — so it is validated here, like the species field is.
    setState(
      () => _model.vaccineError = _model.vaccineText.isEmpty
          ? context.l10n.fieldRequired
          : null,
    );
    if (_model.vaccineText.isEmpty) return;
    if (!(formKey.currentState?.validate() ?? false)) return;

    final ok = await runSave(() async {
      final (user, org) = await requireUserOrg();
      final repo = await ref.read(vaccinationsRepositoryProvider.future);
      final files = await _multipart();
      final v = widget.vaccination;

      if (v == null) {
        await repo.createWithFiles({
          ..._model.payload(),
          'animal': widget.animalId,
          'author': user.id,
          'org': org,
        }, files);
      } else {
        // Never `animal` — it is frozen server-side (1700000087) — and never
        // `org`. A shot recorded on the wrong bird is deleted and re-entered.
        await repo.updateWithFiles(v.id, {
          ..._model.payload(clearing: true),
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
          VaccinationFields(
            model: _model,
            enabled: !isBusy,
            onChanged: markDirty,
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
        ],
      ),
    );
  }
}
