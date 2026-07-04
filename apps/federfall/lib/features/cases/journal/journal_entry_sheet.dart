import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/features/cases/journal/journal_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

/// Opens the journal-entry form as a modal bottom sheet. Exactly one of
/// [caseId] / [aviaryId] must be set — a case-scoped clinical note or an
/// aviary-scoped flock-care log (federfall-d5co.2). Pass [entry] to edit an
/// existing entry; omit it to create a new one. Resolves to `true` when the
/// entry was saved, so the caller can refresh.
Future<bool?> showJournalEntrySheet(
  BuildContext context, {
  String? caseId,
  String? aviaryId,
  JournalEntry? entry,
}) {
  assert(
    (caseId == null) != (aviaryId == null),
    'Exactly one of caseId / aviaryId must be set.',
  );
  return showAppSheet<bool>(
    context,
    builder: (_) =>
        JournalEntrySheet(caseId: caseId, aviaryId: aviaryId, entry: entry),
  );
}

/// Form for creating or editing a dated journal entry with photo attachments
/// (FED-4.7 / journal CRUD; dual-parent since federfall-d5co.2). On edit it
/// shows the existing attachments — each removable — and appends any newly
/// picked photos via a multipart update.
class JournalEntrySheet extends ConsumerStatefulWidget {
  const JournalEntrySheet({this.caseId, this.aviaryId, this.entry, super.key})
    : assert(
        (caseId == null) != (aviaryId == null),
        'Exactly one of caseId / aviaryId must be set.',
      );

  final String? caseId;
  final String? aviaryId;
  final JournalEntry? entry;

  @override
  ConsumerState<JournalEntrySheet> createState() => _JournalEntrySheetState();
}

class _JournalEntrySheetState extends ConsumerState<JournalEntrySheet>
    with DiscardGuard, FormSheetState {
  late final TextEditingController _textController;
  late DateTime _entryAt;

  /// Server-side attachments kept on save (edit only); removing one drops it.
  late final List<String> _existingPhotos;

  /// Freshly picked photos to upload.
  final _newPhotos = <XFile>[];

  bool get _isEditing => widget.entry != null;

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    _textController = TextEditingController(text: entry?.text ?? '');
    _entryAt =
        entry?.entryAt?.toLocal() ??
        entry?.created?.toLocal() ??
        DateTime.now();
    _existingPhotos = [...?entry?.attachments];
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _pickPhotos() async {
    final picker = ref.read(imagePickerProvider);
    final picked = await picker.pickMultiImage();
    if (picked.isNotEmpty) {
      setState(() => _newPhotos.addAll(picked));
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
    final picked = await pickDateTime(context, initial: _entryAt);
    if (picked != null) {
      setState(() => _entryAt = picked);
      markDirty();
    }
  }

  Future<List<http.MultipartFile>> _multipartPhotos() async {
    final files = <http.MultipartFile>[];
    for (final photo in _newPhotos) {
      files.add(
        http.MultipartFile.fromBytes(
          'attachments',
          await photo.readAsBytes(),
          filename: photo.name,
        ),
      );
    }
    return files;
  }

  Future<void> _save() async {
    if (!(formKey.currentState?.validate() ?? false)) return;

    final ok = await runSave(() async {
      final (user, org) = await requireUserOrg();
      final repo = await ref.read(journalRepositoryProvider.future);
      final files = await _multipartPhotos();
      final entry = widget.entry;

      if (entry == null) {
        await repo.createWithFiles({
          if (widget.caseId != null) 'case': widget.caseId,
          if (widget.aviaryId != null) 'aviary': widget.aviaryId,
          'text': _textController.text.trim(),
          'entry_at': _entryAt.toUtc().toIso8601String(),
          'author': user.id,
          'org': org,
        }, files);
      } else {
        await repo.updateWithFiles(entry.id, {
          'text': _textController.text.trim(),
          'entry_at': _entryAt.toUtc().toIso8601String(),
          // Setting the field to the survivors drops any removed attachments;
          // the new uploads are appended on top.
          'attachments': _existingPhotos,
        }, files);
      }

      final caseId = widget.caseId;
      if (caseId != null) ref.invalidate(caseBundleProvider(caseId));
    });
    if (ok && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return guardUnsavedChanges(
      child: SheetScaffold(
        title: _isEditing ? l10n.journalEditTitle : l10n.journalNewTitle,
        formKey: formKey,
        onFormChanged: markDirty,
        isBusy: isBusy,
        error: saveError,
        onSave: _save,
        children: [
          AppTextField(
            controller: _textController,
            label: l10n.journalFieldText,
            enabled: !isBusy,
            validator: Validators.required(l10n),
            minLines: 3,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: AppSpacing.md),
          DateField(
            label: l10n.journalFieldDate,
            value: _entryAt,
            enabled: !isBusy,
            showTime: true,
            onPick: _pickDate,
          ),
          const SizedBox(height: AppSpacing.md),
          if (_existingPhotos.isNotEmpty || _newPhotos.isNotEmpty)
            _PhotoStrip(
              entryId: widget.entry?.id,
              existing: _existingPhotos,
              newPhotos: _newPhotos,
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
                onPressed: isBusy ? null : _pickPhotos,
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(l10n.journalAddPhotos),
              ),
              OutlinedButton.icon(
                onPressed: isBusy ? null : _takePhoto,
                icon: const Icon(Icons.photo_camera_outlined),
                label: Text(l10n.journalTakePhoto),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Preview of the photos staged for the entry: existing server attachments
/// first (network thumbnails), then newly picked local photos. Each is
/// removable.
class _PhotoStrip extends ConsumerWidget {
  const _PhotoStrip({
    required this.entryId,
    required this.existing,
    required this.newPhotos,
    required this.onRemoveExisting,
    required this.onRemoveNew,
  });

  final String? entryId;
  final List<String> existing;
  final List<XFile> newPhotos;
  final ValueChanged<int>? onRemoveExisting;
  final ValueChanged<int>? onRemoveNew;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(journalRepositoryProvider).value;

    return SizedBox(
      height: 88,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          // Keys on both loops: removing photo i must not remount (and
          // re-fetch / re-read) every thumbnail after it.
          for (var i = 0; i < existing.length; i++)
            Padding(
              key: ValueKey(existing[i]),
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: _Thumb(
                onRemove: onRemoveExisting == null
                    ? null
                    : () => onRemoveExisting!(i),
                child: (repo == null || entryId == null)
                    ? const SizedBox(width: 88, height: 88)
                    : CachedFileImage(
                        url: repo.fileUrl(
                          entryId!,
                          existing[i],
                          thumb: '200x200',
                        ),
                        width: 88,
                        height: 88,
                      ),
              ),
            ),
          for (var i = 0; i < newPhotos.length; i++)
            Padding(
              key: ObjectKey(newPhotos[i]),
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: _Thumb(
                onRemove: onRemoveNew == null ? null : () => onRemoveNew!(i),
                child: LocalPhotoThumb(photo: newPhotos[i]),
              ),
            ),
        ],
      ),
    );
  }
}

/// A rounded thumbnail with an optional remove badge.
class _Thumb extends StatelessWidget {
  const _Thumb({required this.child, this.onRemove});

  final Widget child;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(borderRadius: BorderRadius.circular(8), child: child),
        if (onRemove != null)
          Positioned(
            top: -8,
            right: -8,
            child: IconButton(
              icon: const Icon(Icons.cancel),
              iconSize: 20,
              onPressed: onRemove,
            ),
          ),
      ],
    );
  }
}
