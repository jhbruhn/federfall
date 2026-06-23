import 'dart:typed_data';

import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/journal/journal_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

/// Opens the new-journal-entry form as a modal bottom sheet. Resolves to `true`
/// when an entry was saved, so the caller can refresh.
Future<bool?> showNewJournalEntrySheet(
  BuildContext context, {
  required String caseId,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => NewJournalEntrySheet(caseId: caseId),
  );
}

/// Form for adding a dated journal entry with optional photo attachments
/// (FED-4.7). Uploads the photos as multipart files on the new record.
class NewJournalEntrySheet extends ConsumerStatefulWidget {
  const NewJournalEntrySheet({required this.caseId, super.key});

  final String caseId;

  @override
  ConsumerState<NewJournalEntrySheet> createState() =>
      _NewJournalEntrySheetState();
}

class _NewJournalEntrySheetState extends ConsumerState<NewJournalEntrySheet> {
  final _formKey = GlobalKey<FormState>();
  final _textController = TextEditingController();
  final _photos = <XFile>[];
  DateTime _entryAt = DateTime.now();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _pickPhotos() async {
    final picker = ref.read(imagePickerProvider);
    final picked = await picker.pickMultiImage();
    if (picked.isNotEmpty) setState(() => _photos.addAll(picked));
  }

  Future<void> _takePhoto() async {
    final picker = ref.read(imagePickerProvider);
    final shot = await picker.pickImage(source: ImageSource.camera);
    if (shot != null) setState(() => _photos.add(shot));
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _entryAt,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _entryAt = picked);
  }

  Future<List<http.MultipartFile>> _multipartPhotos() async {
    final files = <http.MultipartFile>[];
    for (final photo in _photos) {
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

      final repo = await ref.read(journalRepositoryProvider.future);
      await repo.createWithFiles(
        {
          'case': widget.caseId,
          'text': _textController.text.trim(),
          'entry_at': _entryAt.toUtc().toIso8601String(),
          'author': user.id,
          'org': org,
        },
        await _multipartPhotos(),
      );

      ref.invalidate(journalForCaseProvider(widget.caseId));
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
    final materialL10n = MaterialLocalizations.of(context);

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
              Text(l10n.journalNewTitle, style: theme.textTheme.titleLarge),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                controller: _textController,
                label: l10n.journalFieldText,
                prefixIcon: Icons.notes_outlined,
                enabled: !_busy,
                validator: Validators.required(l10n),
              ),
              const SizedBox(height: AppSpacing.md),
              InkWell(
                onTap: _busy ? null : _pickDate,
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: l10n.journalFieldDate,
                    prefixIcon: const Icon(Icons.event_outlined),
                  ),
                  child: Text(materialL10n.formatMediumDate(_entryAt)),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              if (_photos.isNotEmpty)
                _PhotoStrip(
                  photos: _photos,
                  onRemove: _busy
                      ? null
                      : (i) => setState(() => _photos.removeAt(i)),
                ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _pickPhotos,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: Text(l10n.journalAddPhotos),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _takePhoto,
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: Text(l10n.journalTakePhoto),
                  ),
                ],
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

/// Horizontal preview of the photos staged for upload, each removable.
class _PhotoStrip extends StatelessWidget {
  const _PhotoStrip({required this.photos, required this.onRemove});

  final List<XFile> photos;
  final ValueChanged<int>? onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 88,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: photos.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, i) {
          return Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: FutureBuilder<Uint8List>(
                  future: photos[i].readAsBytes(),
                  builder: (context, snap) {
                    final bytes = snap.data;
                    if (bytes == null) {
                      return const SizedBox(width: 88, height: 88);
                    }
                    return Image.memory(
                      bytes,
                      width: 88,
                      height: 88,
                      fit: BoxFit.cover,
                    );
                  },
                ),
              ),
              if (onRemove != null)
                Positioned(
                  top: -8,
                  right: -8,
                  child: IconButton(
                    icon: const Icon(Icons.cancel),
                    iconSize: 20,
                    onPressed: () => onRemove!(i),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
