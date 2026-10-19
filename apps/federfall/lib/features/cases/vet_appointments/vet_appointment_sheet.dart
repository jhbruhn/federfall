import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/features/cases/journal/journal_providers.dart';
import 'package:federfall/features/cases/vet_appointments/vet_appointment_attachments.dart';
import 'package:federfall/features/reminders/reminder_lead.dart';
import 'package:federfall/features/worklist/worklist_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

/// Opens the vet-appointment add/edit form. Pass [appointment] to edit;
/// [focusOutcome] scrolls the outcome field into focus, for the
/// "add the result" action on the timeline tile.
Future<bool?> showVetAppointmentSheet(
  BuildContext context, {
  required String caseId,
  VetAppointment? appointment,
  bool focusOutcome = false,
}) {
  return showAppSheet<bool>(
    context,
    builder: (_) => VetAppointmentSheet(
      caseId: caseId,
      appointment: appointment,
      focusOutcome: focusOutcome,
    ),
  );
}

/// Form for a vet appointment on a case (federfall-fnpo): when, which practice,
/// why — plus, once the visit is behind us, what came of it.
///
/// The record is written twice in its life, so the form has two faces: before
/// the visit it asks for the appointment and its reminder, after the visit it
/// also offers the outcome. The outcome field is hidden until it can honestly
/// be filled in, because an empty "Ergebnis" box on a future appointment
/// invites writing down a result nobody has yet.
class VetAppointmentSheet extends ConsumerStatefulWidget {
  const VetAppointmentSheet({
    required this.caseId,
    this.appointment,
    this.focusOutcome = false,
    super.key,
  });

  final String caseId;
  final VetAppointment? appointment;
  final bool focusOutcome;

  @override
  ConsumerState<VetAppointmentSheet> createState() =>
      _VetAppointmentSheetState();
}

class _VetAppointmentSheetState extends ConsumerState<VetAppointmentSheet>
    with DiscardGuard, FormSheetState {
  late final TextEditingController _vet;
  late final TextEditingController _reason;
  late final TextEditingController _outcome;
  late DateTime _startsAt;

  /// The per-appointment reminder override: null = follow the device default.
  Duration? _lead;
  late bool _muted;

  /// Stored attachments kept on save; removing one drops it, because the
  /// survivors are sent as the field's new value.
  late final List<String> _existingAttachments;
  final _newAttachments = <XFile>[];

  bool get _isEditing => widget.appointment != null;

  int get _slotsLeft =>
      kVetAppointmentMaxAttachments -
      _existingAttachments.length -
      _newAttachments.length;

  @override
  void initState() {
    super.initState();
    final a = widget.appointment;
    _vet = TextEditingController(text: a?.vet ?? '');
    _reason = TextEditingController(text: a?.reason ?? '');
    _outcome = TextEditingController(text: a?.outcome ?? '');
    // A new appointment defaults to the next full hour tomorrow — nobody books
    // a vet for "right now", and a sensible default is one fewer tap than a
    // picker starting at the current minute.
    _startsAt =
        a?.startsAt?.toLocal() ??
        DateTime(
          DateTime.now().year,
          DateTime.now().month,
          DateTime.now().day + 1,
          9,
        );
    final leadMinutes = a?.reminderLeadMinutes;
    _lead = leadMinutes == null ? null : Duration(minutes: leadMinutes);
    _muted = a?.reminderMuted ?? false;
    _existingAttachments = [...?a?.attachments];
  }

  @override
  void dispose() {
    _vet.dispose();
    _reason.dispose();
    _outcome.dispose();
    super.dispose();
  }

  /// Whether the visit is far enough along that an outcome makes sense: it has
  /// happened, or someone already marked it attended.
  bool get _showOutcome =>
      _isEditing &&
      (widget.appointment!.attendedAt != null ||
          _startsAt.isBefore(DateTime.now()));

  Future<void> _pickStartsAt() async {
    final picked = await pickDateTime(
      context,
      initial: _startsAt,
      // pickDateTime defaults lastDate to today — an appointment is in the
      // future, so it has to be widened explicitly or the picker refuses every
      // date that matters.
      lastDate: DateTime(DateTime.now().year + 2),
    );
    if (picked != null) {
      setState(() => _startsAt = picked);
      markDirty();
    }
  }

  Future<void> _pickLead() async {
    final l10n = context.l10n;
    final picked = await showAppSheet<_LeadChoice>(
      context,
      builder: (_) => _LeadPickerSheet(
        selected: _muted
            ? const _LeadChoice.muted()
            : (_lead == null
                  ? const _LeadChoice.deviceDefault()
                  : _LeadChoice.lead(_lead!)),
        l10n: l10n,
      ),
    );
    if (picked == null) return;
    setState(() {
      _muted = picked.muted;
      // A muted appointment keeps whatever lead was chosen before, so
      // un-muting restores it rather than silently reverting to the default.
      if (!picked.muted) _lead = picked.lead;
    });
    markDirty();
  }

  /// Stages [picked], capped at the slots left — the server rejects an
  /// eleventh file outright, so the cap belongs here rather than in a failed
  /// save after the upload.
  void _stage(List<XFile> picked) {
    if (picked.isEmpty) return;
    setState(() => _newAttachments.addAll(picked.take(_slotsLeft)));
    markDirty();
  }

  Future<void> _pickImages() async =>
      _stage(await ref.read(imagePickerProvider).pickMultiImage());

  Future<void> _takePhoto() async {
    final shot = await ref
        .read(imagePickerProvider)
        .pickImage(source: ImageSource.camera);
    if (shot != null) _stage([shot]);
  }

  Future<void> _pickFiles() async {
    final picked = await ref.read(documentPickerProvider).pickFiles();
    if (!mounted) return;
    final rejected = [
      for (final f in picked)
        if (!isAcceptedVetAttachment(pickedFileName(f))) pickedFileName(f),
    ];
    if (rejected.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.vetAppointmentFileUnsupported(rejected.join(', ')),
          ),
        ),
      );
    }
    _stage([
      for (final f in picked)
        if (isAcceptedVetAttachment(pickedFileName(f))) f,
    ]);
  }

  Future<List<http.MultipartFile>> _multipart() async => [
    for (final file in _newAttachments)
      http.MultipartFile.fromBytes(
        'attachments',
        await file.readAsBytes(),
        filename: pickedFileName(file),
      ),
  ];

  Future<void> _save() async {
    if (!(formKey.currentState?.validate() ?? false)) return;

    final ok = await runSave(() async {
      final (user, org) = await requireUserOrg();
      final repo = await ref.read(vetAppointmentsRepositoryProvider.future);
      final body = <String, dynamic>{
        'starts_at': _startsAt.toUtc().toIso8601String(),
        'vet': _vet.text.trim(),
        'reason': _reason.text.trim(),
        if (_showOutcome) 'outcome': _outcome.text.trim(),
        // PocketBase has no null for a number field, so "follow the device
        // default" is written as the empty value, which reads back as 0 and the
        // mapper turns into null again.
        'reminder_lead_minutes': _lead?.inMinutes ?? '',
        'reminder_muted': _muted,
      };

      final files = await _multipart();
      final existing = widget.appointment;
      if (existing == null) {
        await repo.createWithFiles({
          ...body,
          'case': widget.caseId,
          'created_by': user.id,
          'org': org,
        }, files);
      } else {
        await repo.updateWithFiles(existing.id, {
          ...body,
          // The survivors; the new uploads are appended on top.
          'attachments': _existingAttachments,
        }, files);
      }

      ref
        ..invalidate(caseBundleProvider(widget.caseId))
        ..invalidate(worklistSourceProvider);
    });
    if (ok && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return guardUnsavedChanges(
      child: SheetScaffold(
        title: _isEditing
            ? l10n.vetAppointmentEditTitle
            : l10n.vetAppointmentNewTitle,
        formKey: formKey,
        onFormChanged: markDirty,
        isBusy: isBusy,
        error: saveError,
        onSave: _save,
        children: [
          DateField(
            label: l10n.vetAppointmentStartsAtLabel,
            value: _startsAt,
            enabled: !isBusy,
            showTime: true,
            onPick: _pickStartsAt,
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _vet,
            label: l10n.vetAppointmentVetLabel,
            enabled: !isBusy,
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _reason,
            label: l10n.vetAppointmentReasonLabel,
            enabled: !isBusy,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
          ),
          if (_showOutcome) ...[
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              controller: _outcome,
              label: l10n.vetAppointmentOutcomeLabel,
              enabled: !isBusy,
              autofocus: widget.focusOutcome,
              minLines: 3,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          _AttachmentsEditor(
            appointmentId: widget.appointment?.id,
            existing: _existingAttachments,
            added: _newAttachments,
            enabled: !isBusy,
            canAdd: _slotsLeft > 0,
            onRemoveExisting: (name) {
              setState(() => _existingAttachments.remove(name));
              markDirty();
            },
            onRemoveAdded: (file) {
              setState(() => _newAttachments.remove(file));
              markDirty();
            },
            onPickImages: _pickImages,
            onTakePhoto: _takePhoto,
            onPickFiles: _pickFiles,
          ),
          const Divider(height: AppSpacing.lg),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.notifications_outlined),
            title: Text(l10n.vetAppointmentReminderLabel),
            subtitle: Text(l10n.vetAppointmentReminderScopeHint),
            trailing: Text(
              _muted
                  ? l10n.vetAppointmentReminderNone
                  : (_lead == null
                        ? l10n.vetAppointmentReminderDefault
                        : reminderLeadLabel(l10n, _lead!)),
            ),
            onTap: isBusy ? null : _pickLead,
          ),
        ],
      ),
    );
  }
}

/// The attachments section of the form: pictures in the shared photo strip,
/// every other file as a named chip, then the three ways to add one.
///
/// Split in two because the shared strip only knows images and videos — a PDF
/// handed to it would be fetched as a "thumbnail", i.e. downloaded whole, and
/// then fail to decode.
class _AttachmentsEditor extends ConsumerWidget {
  const _AttachmentsEditor({
    required this.appointmentId,
    required this.existing,
    required this.added,
    required this.enabled,
    required this.canAdd,
    required this.onRemoveExisting,
    required this.onRemoveAdded,
    required this.onPickImages,
    required this.onTakePhoto,
    required this.onPickFiles,
  });

  final String? appointmentId;
  final List<String> existing;
  final List<XFile> added;
  final bool enabled;
  final bool canAdd;
  final ValueChanged<String> onRemoveExisting;
  final ValueChanged<XFile> onRemoveAdded;
  final VoidCallback onPickImages;
  final VoidCallback onTakePhoto;
  final VoidCallback onPickFiles;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final repo = ref.watch(vetAppointmentsRepositoryProvider).value;
    final id = appointmentId;

    final existingImages = existing.where(isPreviewableImage).toList();
    final existingFiles = existing.where((f) => !isPreviewableImage(f));
    final addedImages = added
        .where((f) => isPreviewableImage(pickedFileName(f)))
        .toList();
    final addedFiles = added.where(
      (f) => !isPreviewableImage(pickedFileName(f)),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.vetAppointmentAttachmentsLabel,
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: AppSpacing.xs),
        if (existingImages.isNotEmpty || addedImages.isNotEmpty)
          EditablePhotoStrip(
            existing: existingImages,
            newPhotos: addedImages,
            thumbUrl: repo == null || id == null
                ? null
                : (f) => repo.fileUrl(id, f, thumb: '200x200'),
            onRemoveExisting: enabled
                ? (i) => onRemoveExisting(existingImages[i])
                : null,
            onRemoveNew: enabled ? (i) => onRemoveAdded(addedImages[i]) : null,
          ),
        if (existingFiles.isNotEmpty || addedFiles.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                for (final f in existingFiles)
                  AttachmentFileChip(
                    key: ValueKey(f),
                    name: attachmentDisplayName(f),
                    onRemove: enabled ? () => onRemoveExisting(f) : null,
                  ),
                for (final f in addedFiles)
                  AttachmentFileChip(
                    key: ObjectKey(f),
                    name: pickedFileName(f),
                    onRemove: enabled ? () => onRemoveAdded(f) : null,
                  ),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            OutlinedButton.icon(
              onPressed: enabled && canAdd ? onPickImages : null,
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(l10n.vetAppointmentAddImage),
            ),
            OutlinedButton.icon(
              onPressed: enabled && canAdd ? onTakePhoto : null,
              icon: const Icon(Icons.photo_camera_outlined),
              label: Text(l10n.vetAppointmentTakePhoto),
            ),
            OutlinedButton.icon(
              onPressed: enabled && canAdd ? onPickFiles : null,
              icon: const Icon(Icons.attach_file),
              label: Text(l10n.vetAppointmentAddFile),
            ),
          ],
        ),
      ],
    );
  }
}

/// The reminder choice for one appointment: the device default, an explicit
/// lead, or no reminder at all.
@immutable
class _LeadChoice {
  const _LeadChoice.deviceDefault() : lead = null, muted = false;
  const _LeadChoice.lead(Duration this.lead) : muted = false;
  const _LeadChoice.muted() : lead = null, muted = true;

  final Duration? lead;
  final bool muted;

  @override
  bool operator ==(Object other) =>
      other is _LeadChoice && other.lead == lead && other.muted == muted;

  @override
  int get hashCode => Object.hash(lead, muted);
}

class _LeadPickerSheet extends StatelessWidget {
  const _LeadPickerSheet({required this.selected, required this.l10n});

  final _LeadChoice selected;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final choices = <(_LeadChoice, String)>[
      (const _LeadChoice.deviceDefault(), l10n.vetAppointmentReminderDefault),
      for (final lead in kReminderLeadChoices)
        (_LeadChoice.lead(lead), reminderLeadLabel(l10n, lead)),
      (const _LeadChoice.muted(), l10n.vetAppointmentReminderNone),
    ];

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: Text(
                l10n.vetAppointmentReminderLabel,
                style: theme.textTheme.titleLarge,
              ),
            ),
            RadioGroup<_LeadChoice>(
              groupValue: selected,
              onChanged: (value) => Navigator.of(context).pop(value),
              child: Column(
                children: [
                  for (final (choice, label) in choices)
                    RadioListTile<_LeadChoice>(
                      value: choice,
                      title: Text(label),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }
}
