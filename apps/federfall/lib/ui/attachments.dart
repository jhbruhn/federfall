import 'dart:async';

import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/theme/app_spacing.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:zugvogel_pb_client/zugvogel_pb_client.dart'
    show fileTokenProvider;
import 'package:zugvogel_ui/zugvogel_ui.dart'
    show
        CachedFileImage,
        VideoAttachmentThumb,
        isVideoAttachment,
        showImageViewer;

/// How a stored attachment is drawn and opened. Decided by extension, because
/// that is all a stored filename carries.
enum AttachmentKind {
  /// Thumbnailed, and opened in the in-app viewer.
  image,

  /// A placeholder tile, opened by the OS (the app has no video player).
  video,

  /// A named chip, opened by the OS or the browser — a PDF Befund, a scan.
  document,
}

/// The extensions PocketBase makes a thumbnail of AND Flutter decodes on every
/// platform. Everything else that is not a video — a PDF, but also a HEIC or
/// TIFF — is a [AttachmentKind.document]: `?thumb=` on a non-thumbable file
/// silently serves the ORIGINAL (the 1700000049 finding), so asking for one
/// would download a whole scan to paint a tile.
const Set<String> _imageExtensions = {'jpg', 'jpeg', 'png', 'webp', 'gif'};

String _extensionOf(String name) {
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
}

AttachmentKind attachmentKindOf(String nameOrPath) {
  if (isVideoAttachment(nameOrPath)) return AttachmentKind.video;
  if (_imageExtensions.contains(_extensionOf(nameOrPath))) {
    return AttachmentKind.image;
  }
  return AttachmentKind.document;
}

/// Whether [nameOrPath] is a picture this app draws as a thumbnail.
bool isImageAttachment(String nameOrPath) =>
    attachmentKindOf(nameOrPath) == AttachmentKind.image;

/// The extension of [nameOrPath], lower-cased, without the dot ('' if none).
String attachmentExtension(String nameOrPath) => _extensionOf(nameOrPath);

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
/// counterpart of `imagePickerProvider` for everything that is not a photo.
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

/// The files of one file field while a form edits them: the [existing]
/// filenames still stored on the record, and the [added] files picked since.
///
/// Every form with attachments — journal, vaccination, egg record, microscopy,
/// vet appointment, intake — used to restate this: pick, cap at the server's
/// `maxSelect`, remove, and turn the new files into multipart parts. A save
/// sends [existing] as the field's value (which is what drops a removed file)
/// and [multipart] on top.
///
/// [onChanged] runs after every change the user made, so the owning form can
/// `setState` and mark itself dirty; it is not called for a pick that came
/// back empty.
class AttachmentDraft {
  AttachmentDraft({
    required this.field,
    required this.max,
    required this.onChanged,
    Iterable<String> existing = const [],
  }) : existing = [...existing];

  /// The record's file field, e.g. `attachments` or `photos`.
  final String field;

  /// The field's `maxSelect`. The server rejects one file more outright, so
  /// the cap belongs at staging time rather than in a failed save after the
  /// upload.
  final int max;

  final VoidCallback onChanged;

  final List<String> existing;
  final List<XFile> added = [];

  int get slotsLeft => max - existing.length - added.length;

  bool get canAdd => slotsLeft > 0;

  bool get isEmpty => existing.isEmpty && added.isEmpty;

  /// Stages [picked], capped at the slots left.
  void stage(Iterable<XFile> picked) {
    final take = picked.take(slotsLeft).toList();
    if (take.isEmpty) return;
    added.addAll(take);
    onChanged();
  }

  Future<void> pickImages(ImagePicker picker) async =>
      stage(await picker.pickMultiImage());

  Future<void> takePhoto(ImagePicker picker) async =>
      stage([?await picker.pickImage(source: ImageSource.camera)]);

  Future<void> pickVideo(ImagePicker picker, ImageSource source) async =>
      stage([?await picker.pickVideo(source: source)]);

  void removeExisting(String filename) {
    existing.remove(filename);
    onChanged();
  }

  void removeAdded(XFile file) {
    added.remove(file);
    onChanged();
  }

  /// The [added] files as multipart parts on [field].
  Future<List<http.MultipartFile>> multipart() async => [
    for (final file in added)
      http.MultipartFile.fromBytes(
        field,
        await file.readAsBytes(),
        filename: pickedFileName(file),
      ),
  ];
}

/// Resolves a stored file's 200x200 thumbnail for an edit form's photo strip;
/// `null` until [repo] has resolved, and on create, where there is no record
/// (and so nothing stored) yet.
Uri Function(String)? storedThumbUrl(
  PbReadOnlyRepository<Object?>? repo,
  String? recordId,
) {
  if (repo == null || recordId == null) return null;
  return (filename) => repo.fileUrl(recordId, filename, thumb: '200x200');
}

/// Opens stored attachment [filename] of record [recordId] in [repo]'s
/// collection — the one way every protected file field here is opened.
///
/// An [AttachmentKind.image] goes to the in-app viewer alongside the record's
/// other images; the viewer's URLs stay token-free because
/// `ProtectedFileCacheManager` appends the token at download time. Anything
/// else (a video, a PDF) is handed to the OS or the browser via `url_launcher`
/// with a file token: the app carries no video player or PDF viewer, and the
/// tokenised URL is good for about two minutes, which is ample for a launch
/// (federfall-ewcf tracks an inline video player, and records that
/// `web_headers.pb.js` has no `media-src` directive today).
Future<void> openProtectedAttachment(
  BuildContext context,
  WidgetRef ref, {
  required PbReadOnlyRepository<Object?> repo,
  required String recordId,
  required List<String> attachments,
  required String filename,
}) async {
  if (isImageAttachment(filename)) {
    final images = attachments.where(isImageAttachment).toList();
    await showImageViewer(
      context,
      imageUrls: [for (final f in images) repo.fileUrl(recordId, f).toString()],
      initialIndex: images.indexOf(filename),
    );
    return;
  }

  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  final token = await ref.read(fileTokenProvider.future);
  final url = repo.fileUrl(recordId, filename, token: token);
  final launched = await launchUrl(url, mode: LaunchMode.externalApplication);
  if (!launched) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.attachmentOpenFailed)));
  }
}

/// A stored or staged [AttachmentKind.document], as a chip carrying its name.
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
    // InputChip, not ActionChip: the edit forms need the delete badge, and one
    // widget keeps the two places looking alike.
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: InputChip(
        avatar: Icon(attachmentIcon(name), size: 18),
        label: Text(name, overflow: TextOverflow.ellipsis),
        onPressed: onOpen,
        onDeleted: onRemove,
      ),
    );
  }
}

/// The stored attachments of one record on a timeline tile: images and videos
/// as a row of thumbnails, every other file as a named chip below it. Tapping
/// either opens it via [openProtectedAttachment].
///
/// Every record kind with a protected file field draws its files with this —
/// journal entries, vaccinations, egg records, microscopy samples and vet
/// appointments — so a fix to one (the opaque hit test, the never-a-thumb-of-
/// a-video rule) is a fix to all.
class AttachmentStrip extends ConsumerWidget {
  const AttachmentStrip({
    required this.repo,
    required this.recordId,
    required this.files,
    super.key,
  });

  /// The record's repository; `null` while it resolves, which holds the strip's
  /// space with a spinner rather than flashing error tiles.
  final PbReadOnlyRepository<Object?>? repo;
  final String recordId;
  final List<String> files;

  static const double _size = 96;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = this.repo;
    if (repo == null) {
      return const SizedBox(
        height: _size,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final thumbs = [
      for (final f in files)
        if (attachmentKindOf(f) != AttachmentKind.document) f,
    ];
    final documents = [
      for (final f in files)
        if (attachmentKindOf(f) == AttachmentKind.document) f,
    ];

    void open(String filename) => unawaited(
      openProtectedAttachment(
        context,
        ref,
        repo: repo,
        recordId: recordId,
        attachments: files,
        filename: filename,
      ),
    );

    // The files are protected, but the access token is appended at download
    // time (ProtectedFileCacheManager), so these URLs stay token-free and
    // cached thumbnails render without minting one.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (thumbs.isNotEmpty)
          SizedBox(
            height: _size,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: thumbs.length,
              separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
              itemBuilder: (context, i) => Semantics(
                button: true,
                label: context.l10n.photoViewLabel(i + 1, thumbs.length),
                child: GestureDetector(
                  // Opaque, not the default deferToChild: the thumbnail only
                  // reports a hit once CachedFileImage has decoded a frame, so
                  // while loading (or after a load failure) the tap would be
                  // silently swallowed (federfall-ltfw).
                  behavior: HitTestBehavior.opaque,
                  onTap: () => open(thumbs[i]),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    // Never a thumbnail request for a video: `?thumb=` on a
                    // non-image serves the ORIGINAL, i.e. the whole clip.
                    child: isVideoAttachment(thumbs[i])
                        ? const VideoAttachmentThumb(size: _size)
                        : CachedFileImage(
                            url: repo.fileUrl(
                              recordId,
                              thumbs[i],
                              thumb: '200x200',
                            ),
                            width: _size,
                            height: _size,
                          ),
                  ),
                ),
              ),
            ),
          ),
        if (thumbs.isNotEmpty && documents.isNotEmpty)
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
