import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens one attachment of microscopy sample [sampleId].
///
/// An image goes to the in-app viewer, which knows how to mint the file token
/// at download time. A **video** is handed to the OS or the browser via
/// `url_launcher` instead: the app carries no `video_player` dependency, and
/// the tokenised URL is good for about two minutes, which is ample for a
/// launch (federfall-ewcf tracks an inline player, and records that
/// `web_headers.pb.js` has no `media-src` directive today).
Future<void> openMicroscopyAttachment(
  BuildContext context,
  WidgetRef ref, {
  required String sampleId,
  required List<String> attachments,
  required int index,
}) async {
  final filename = attachments[index];
  final repo = await ref.read(microscopySamplesRepositoryProvider.future);
  if (!context.mounted) return;

  if (!isVideoAttachment(filename)) {
    // The viewer's URLs stay token-free; ProtectedFileCacheManager appends the
    // token at download time.
    await showImageViewer(
      context,
      imageUrls: [
        for (final f in attachments)
          if (!isVideoAttachment(f)) repo.fileUrl(sampleId, f).toString(),
      ],
      initialIndex: [
        for (final f in attachments)
          if (!isVideoAttachment(f)) f,
      ].indexOf(filename),
    );
    return;
  }

  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  final token = await ref.read(fileTokenProvider.future);
  final url = repo.fileUrl(sampleId, filename, token: token);
  final launched = await launchUrl(url, mode: LaunchMode.externalApplication);
  if (!launched) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.microscopyOpenFailed)));
  }
}
