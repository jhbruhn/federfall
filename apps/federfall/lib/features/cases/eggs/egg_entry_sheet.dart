import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/cases_labels.dart';
import 'package:federfall/features/cases/eggs/eggs_providers.dart';
import 'package:federfall/features/cases/journal/journal_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

/// Opens the egg-laying form as a modal bottom sheet. Pass [egg] to edit an
/// existing record; omit it to log a new one. Resolves to `true` on save.
///
/// There is no `caseId` parameter anywhere in this feature: an egg belongs to
/// the animal, and the case timelines it appears on are derived from the date
/// (see [eggsForCase]).
Future<bool?> showEggEntrySheet(
  BuildContext context, {
  required String animalId,
  EggRecord? egg,
}) {
  return showAppSheet<bool>(
    context,
    builder: (_) => EggEntrySheet(animalId: animalId, egg: egg),
  );
}

/// Form for logging or editing one egg-laying event (federfall-4agw): the date,
/// how many eggs, fertility, what happened to them, whether the layer is only
/// presumed, up to three photos (e.g. of a Windei) and a note.
class EggEntrySheet extends ConsumerStatefulWidget {
  const EggEntrySheet({required this.animalId, this.egg, super.key});

  final String animalId;
  final EggRecord? egg;

  /// PocketBase caps `egg_records.photos` at three files (1700000056).
  static const int maxPhotos = 3;

  @override
  ConsumerState<EggEntrySheet> createState() => _EggEntrySheetState();
}

class _EggEntrySheetState extends ConsumerState<EggEntrySheet>
    with DiscardGuard, FormSheetState {
  late final TextEditingController _notesController;
  late DateTime _laidAt;
  late int _count;
  late EggFertility _fertility;
  late EggFate _fate;
  late bool _uncertain;

  /// Server-side photos kept on save (edit only); removing one drops it.
  late final List<String> _existingPhotos;

  /// Freshly picked photos to upload.
  final _newPhotos = <XFile>[];

  bool get _isEditing => widget.egg != null;

  int get _photoCount => _existingPhotos.length + _newPhotos.length;

  int get _photoSlotsLeft => EggEntrySheet.maxPhotos - _photoCount;

  @override
  void initState() {
    super.initState();
    final egg = widget.egg;
    _notesController = TextEditingController(text: egg?.notes ?? '');
    _laidAt = (egg?.laidAt ?? egg?.created)?.toLocal() ?? DateTime.now();
    _count = egg?.count ?? 1;
    _fertility = egg?.fertility ?? EggFertility.unknown;
    _fate = egg?.fate ?? EggFate.unknown;
    _uncertain = egg?.attribution == EggAttribution.presumed;
    _existingPhotos = [...?egg?.photos];
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickPhotos() async {
    final picker = ref.read(imagePickerProvider);
    final picked = await picker.pickMultiImage();
    if (picked.isNotEmpty) {
      // The server rejects a fourth file outright, so cap the selection here
      // rather than let the save fail after the upload.
      setState(() => _newPhotos.addAll(picked.take(_photoSlotsLeft)));
      markDirty();
    }
  }

  Future<void> _takePhoto() async {
    final picker = ref.read(imagePickerProvider);
    final shot = await picker.pickImage(source: ImageSource.camera);
    if (shot != null) {
      setState(() => _newPhotos.add(shot));
      markDirty();
    }
  }

  Future<void> _pickDate() async {
    final picked = await pickDate(context, initial: _laidAt);
    if (picked != null) {
      setState(() => _laidAt = picked);
      markDirty();
    }
  }

  void _setCount(int value) {
    setState(() => _count = value);
    markDirty();
  }

  Future<List<http.MultipartFile>> _multipartPhotos() async {
    final files = <http.MultipartFile>[];
    for (final photo in _newPhotos) {
      files.add(
        http.MultipartFile.fromBytes(
          'photos',
          await photo.readAsBytes(),
          filename: photo.name,
        ),
      );
    }
    return files;
  }

  /// Resolves stored photo thumbnails; null until the repository (and, on
  /// create, the record) exists.
  Uri Function(String)? _thumbUrl() {
    final repo = ref.watch(eggRecordsRepositoryProvider).value;
    final eggId = widget.egg?.id;
    if (repo == null || eggId == null) return null;
    return (filename) => repo.fileUrl(eggId, filename, thumb: '200x200');
  }

  Future<void> _save() async {
    if (!(formKey.currentState?.validate() ?? false)) return;

    final ok = await runSave(() async {
      final (user, org) = await requireUserOrg();
      final repo = await ref.read(eggRecordsRepositoryProvider.future);
      final files = await _multipartPhotos();
      final notes = _notesController.text.trim();
      final egg = widget.egg;
      final attribution = _uncertain
          ? EggAttribution.presumed
          : EggAttribution.confirmed;

      if (egg == null) {
        await repo.createWithFiles({
          'animal': widget.animalId,
          'laid_at': _laidAt.toUtc().toIso8601String(),
          'count': _count,
          'fertility': _fertility.wire,
          'fate': _fate.wire,
          'attribution': attribution.wire,
          'notes': ?(notes.isEmpty ? null : notes),
          'author': user.id,
          'org': org,
        }, files);
      } else {
        // Never `animal` (that is reassignment) and never `org`.
        await repo.updateWithFiles(egg.id, {
          'laid_at': _laidAt.toUtc().toIso8601String(),
          'count': _count,
          'fertility': _fertility.wire,
          'fate': _fate.wire,
          'attribution': attribution.wire,
          'notes': notes,
          // Setting the field to the survivors drops any removed photo; the
          // new uploads are appended on top.
          'photos': _existingPhotos,
        }, files);
      }

      ref.invalidate(eggsForAnimalProvider(widget.animalId));
    });
    if (ok && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return guardUnsavedChanges(
      child: SheetScaffold(
        title: _isEditing ? l10n.eggEditTitle : l10n.eggNewTitle,
        formKey: formKey,
        onFormChanged: markDirty,
        isBusy: isBusy,
        error: saveError,
        onSave: _save,
        children: [
          DateField(
            label: l10n.eggFieldDate,
            value: _laidAt,
            enabled: !isBusy,
            onPick: _pickDate,
          ),
          const SizedBox(height: AppSpacing.md),
          _CountStepper(
            label: l10n.eggFieldCount,
            value: _count,
            enabled: !isBusy,
            onChanged: _setCount,
          ),
          const SizedBox(height: AppSpacing.md),
          DropdownButtonFormField<EggFertility>(
            initialValue: _fertility,
            decoration: InputDecoration(
              labelText: l10n.eggFieldFertility,
              prefixIcon: const Icon(Icons.egg_alt_outlined),
            ),
            items: [
              for (final f in EggFertility.values)
                DropdownMenuItem(
                  value: f,
                  child: Text(eggFertilityLabel(l10n, f)),
                ),
            ],
            onChanged: isBusy
                ? null
                : (f) => setState(() => _fertility = f ?? _fertility),
          ),
          const SizedBox(height: AppSpacing.md),
          DropdownButtonFormField<EggFate>(
            initialValue: _fate,
            decoration: InputDecoration(
              labelText: l10n.eggFieldFate,
              prefixIcon: const Icon(Icons.outbound_outlined),
            ),
            items: [
              for (final f in EggFate.values)
                DropdownMenuItem(value: f, child: Text(eggFateLabel(l10n, f))),
            ],
            onChanged: isBusy
                ? null
                : (f) => setState(() => _fate = f ?? _fate),
          ),
          const SizedBox(height: AppSpacing.sm),
          SwitchListTile(
            value: _uncertain,
            title: Text(l10n.eggFieldUncertain),
            subtitle: Text(l10n.eggFieldUncertainHint),
            contentPadding: EdgeInsets.zero,
            onChanged: isBusy
                ? null
                : (v) {
                    setState(() => _uncertain = v);
                    markDirty();
                  },
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(l10n.eggPhotosLabel, style: theme.textTheme.labelLarge),
          const SizedBox(height: AppSpacing.xs),
          if (_photoCount > 0)
            EditablePhotoStrip(
              existing: _existingPhotos,
              newPhotos: _newPhotos,
              thumbUrl: _thumbUrl(),
              onRemoveExisting: isBusy
                  ? null
                  : (i) {
                      setState(() => _existingPhotos.removeAt(i));
                      markDirty();
                    },
              onRemoveNew: isBusy
                  ? null
                  : (i) {
                      setState(() => _newPhotos.removeAt(i));
                      markDirty();
                    },
            ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              OutlinedButton.icon(
                onPressed: isBusy || _photoSlotsLeft == 0 ? null : _pickPhotos,
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(l10n.eggAddPhoto),
              ),
              OutlinedButton.icon(
                onPressed: isBusy || _photoSlotsLeft == 0 ? null : _takePhoto,
                icon: const Icon(Icons.photo_camera_outlined),
                label: Text(l10n.eggTakePhoto),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _notesController,
            label: l10n.eggFieldNotes,
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

/// A minus/plus stepper for the egg count. A stepper rather than a text field:
/// the value is almost always 1 or 2, and the server enforces a minimum of 1.
class _CountStepper extends StatelessWidget {
  const _CountStepper({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final int value;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.egg_outlined),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              context.l10n.eggCountLabel(value),
              style: theme.textTheme.bodyLarge,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            tooltip: context.l10n.eggCountDecrease,
            onPressed: enabled && value > 1 ? () => onChanged(value - 1) : null,
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: context.l10n.eggCountIncrease,
            onPressed: enabled ? () => onChanged(value + 1) : null,
          ),
        ],
      ),
    );
  }
}
