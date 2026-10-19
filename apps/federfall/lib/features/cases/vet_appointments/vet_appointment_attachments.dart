import 'dart:async';

import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

/// PocketBase caps `vet_appointments.attachments` at ten files (1700000094).
const int kVetAppointmentMaxAttachments = 10;

/// What `vet_appointments.attachments` admits, by extension — the client-side
/// mirror of 1700000094's MIME allowlist, checked before a file is staged so a
/// wrong pick is refused with its name rather than as a failed save. The server
/// sniffs the content and stays the authority.
///
/// Keyed by extension because that is all a picked file reliably carries; the
/// MIME values exist so `vet_appointment_attachments_test.dart` can hold this
/// map and the migration's list to the SAME set — add a type in one place and
/// that test fails until the other agrees.
const Map<String, String> kVetAppointmentFileTypes = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
  'gif': 'image/gif',
  'heic': 'image/heic',
  'heif': 'image/heif',
  'tif': 'image/tiff',
  'tiff': 'image/tiff',
  'bmp': 'image/bmp',
  'pdf': 'application/pdf',
  'dcm': 'application/dicom',
  'doc': 'application/msword',
  'docx':
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xls': 'application/vnd.ms-excel',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'odt': 'application/vnd.oasis.opendocument.text',
  'ods': 'application/vnd.oasis.opendocument.spreadsheet',
  'txt': 'text/plain',
  'csv': 'text/csv',
  'zip': 'application/zip',
};

/// The extensions PocketBase makes a thumbnail of AND Flutter can decode on
/// every platform. Everything else — a PDF, but also a HEIC or TIFF — is shown
/// as a named file: `?thumb=` on a non-thumbable file silently serves the
/// ORIGINAL (the 1700000049 finding), so asking for one would download a whole
/// scan to paint a tile.
const Set<String> _previewableExtensions = {
  'jpg',
  'jpeg',
  'png',
  'webp',
  'gif',
};

String _extensionOf(String name) {
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
}

/// Whether [nameOrPath] is a picture this app draws as a thumbnail.
bool isPreviewableImage(String nameOrPath) =>
    _previewableExtensions.contains(_extensionOf(nameOrPath));

/// Whether a picked file may be uploaded at all (see
/// [kVetAppointmentFileTypes]).
bool isAcceptedVetAttachment(String nameOrPath) =>
    kVetAppointmentFileTypes.containsKey(_extensionOf(nameOrPath));

/// A picked file's name. `XFile.name` can be empty (it is for
/// `XFile.fromData` in tests), so fall back to the path — both carry the
/// extension everything here decides on.
String pickedFileName(XFile file) =>
    file.name.isNotEmpty ? file.name : file.path;

/// A stored filename as the user named it: PocketBase appends `_` plus a
/// ten-character random suffix before the extension, which means nothing to a
/// reader looking for "befund.pdf".
String attachmentDisplayName(String stored) =>
    stored.replaceFirst(RegExp(r'_[A-Za-z0-9]{10}(?=\.[^.]+$)'), '');

IconData attachmentIcon(String name) => switch (_extensionOf(name)) {
  'pdf' => Icons.picture_as_pdf_outlined,
  'doc' || 'docx' || 'odt' || 'txt' => Icons.description_outlined,
  'xls' || 'xlsx' || 'ods' || 'csv' => Icons.table_chart_outlined,
  'zip' => Icons.folder_zip_outlined,
  'heic' || 'heif' || 'tif' || 'tiff' || 'bmp' || 'dcm' => Icons.image_outlined,
  _ => Icons.insert_drive_file_outlined,
};

/// Picks arbitrary files, injectable so tests can supply a fake — the
/// counterpart of `imagePickerProvider` for the non-image half.
class DocumentPicker {
  const DocumentPicker();

  /// The picked files, or empty when the user backed out.
  Future<List<XFile>> pickFiles() async => [
    for (final f in await FilePicker.pickFiles()) f.xFile,
  ];
}

final documentPickerProvider = Provider<DocumentPicker>(
  (ref) => const DocumentPicker(),
);

/// Opens stored attachment [filename] of appointment [appointmentId]: a
/// picture in the in-app viewer, anything else (a PDF Befund) externally.
Future<void> openVetAppointmentAttachment(
  BuildContext context,
  WidgetRef ref, {
  required String appointmentId,
  required List<String> attachments,
  required String filename,
}) async {
  final repo = await ref.read(vetAppointmentsRepositoryProvider.future);
  if (!context.mounted) return;
  await openProtectedAttachment(
    context,
    ref,
    repo: repo,
    recordId: appointmentId,
    attachments: attachments,
    filename: filename,
    showsInViewer: isPreviewableImage,
  );
}

/// A stored or staged non-image file, as a chip carrying its name.
class AttachmentFileChip extends StatelessWidget {
  const AttachmentFileChip({
    required this.name,
    this.onOpen,
    this.onRemove,
    super.key,
  });

  final String name;
  final VoidCallback? onOpen;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final avatar = Icon(attachmentIcon(name), size: 18);
    final label = Text(name, overflow: TextOverflow.ellipsis);
    // InputChip, not ActionChip: the edit form needs the delete badge, and one
    // widget keeps the two places looking alike.
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: InputChip(
        avatar: avatar,
        label: label,
        onPressed: onOpen,
        onDeleted: onRemove,
      ),
    );
  }
}

/// The attachments on an appointment's timeline tile: pictures as thumbnails,
/// every other file as a named chip. Tapping either opens it.
class VetAppointmentAttachments extends ConsumerWidget {
  const VetAppointmentAttachments({required this.appointment, super.key});

  final VetAppointment appointment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(vetAppointmentsRepositoryProvider).value;
    final files = appointment.attachments;
    final images = files.where(isPreviewableImage).toList();
    final documents = files.where((f) => !isPreviewableImage(f)).toList();

    void open(String filename) => unawaited(
      openVetAppointmentAttachment(
        context,
        ref,
        appointmentId: appointment.id,
        attachments: files,
        filename: filename,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (images.isNotEmpty)
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: images.length,
              separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
              itemBuilder: (context, i) => Semantics(
                button: true,
                label: context.l10n.photoViewLabel(i + 1, images.length),
                child: GestureDetector(
                  // Opaque, not deferToChild: the thumbnail only reports a hit
                  // once it has decoded a frame (federfall-ltfw).
                  behavior: HitTestBehavior.opaque,
                  onTap: () => open(images[i]),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    // `attachments` is protected (1700000094); the token is
                    // appended at download time, so these URLs stay token-free.
                    child: repo == null
                        ? const SizedBox(width: 96, height: 96)
                        : CachedFileImage(
                            url: repo.fileUrl(
                              appointment.id,
                              images[i],
                              thumb: '200x200',
                            ),
                            width: 96,
                            height: 96,
                          ),
                  ),
                ),
              ),
            ),
          ),
        if (images.isNotEmpty && documents.isNotEmpty)
          const SizedBox(height: AppSpacing.xs),
        if (documents.isNotEmpty)
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              for (final f in documents)
                AttachmentFileChip(
                  name: attachmentDisplayName(f),
                  onOpen: () => open(f),
                ),
            ],
          ),
      ],
    );
  }
}
