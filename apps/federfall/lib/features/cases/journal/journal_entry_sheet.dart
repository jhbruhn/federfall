import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/features/cases/journal/journal_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  /// PocketBase caps `journal_entries.attachments` at twenty files
  /// (1700000007).
  static const int maxAttachments = 20;

  @override
  ConsumerState<JournalEntrySheet> createState() => _JournalEntrySheetState();
}

class _JournalEntrySheetState extends ConsumerState<JournalEntrySheet>
    with DiscardGuard, FormSheetState {
  late final TextEditingController _textController;
  late DateTime _entryAt;

  late final AttachmentDraft _photos;

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
    _photos = AttachmentDraft(
      field: 'attachments',
      max: JournalEntrySheet.maxAttachments,
      existing: entry?.attachments ?? const [],
      onChanged: () {
        setState(() {});
        markDirty();
      },
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await pickDateTime(context, initial: _entryAt);
    if (picked != null) {
      setState(() => _entryAt = picked);
      markDirty();
    }
  }

  Future<void> _save() async {
    if (!(formKey.currentState?.validate() ?? false)) return;

    final ok = await runSave(() async {
      final (user, org) = await requireUserOrg();
      final repo = await ref.read(journalRepositoryProvider.future);
      final files = await _photos.multipart();
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
          'attachments': _photos.existing,
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
          if (!_photos.isEmpty)
            EditablePhotoStrip(
              existing: _photos.existing,
              newPhotos: _photos.added,
              thumbUrl: storedThumbUrl(
                ref.watch(journalRepositoryProvider).value,
                widget.entry?.id,
              ),
              onRemoveExisting: isBusy
                  ? null
                  : (i) => _photos.removeExisting(_photos.existing[i]),
              onRemoveNew: isBusy
                  ? null
                  : (i) => _photos.removeAdded(_photos.added[i]),
            ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              OutlinedButton.icon(
                onPressed: isBusy || !_photos.canAdd
                    ? null
                    : () => _photos.pickImages(ref.read(imagePickerProvider)),
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(l10n.journalAddPhotos),
              ),
              OutlinedButton.icon(
                onPressed: isBusy || !_photos.canAdd
                    ? null
                    : () => _photos.takePhoto(ref.read(imagePickerProvider)),
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
