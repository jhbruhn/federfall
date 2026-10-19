import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:zugvogel_pb_client/zugvogel_pb_client.dart'
    show fileTokenProvider;
import 'package:zugvogel_ui/zugvogel_ui.dart' show showImageViewer;

/// Opens stored attachment [filename] of record [recordId] in [repo]'s
/// collection — the one way every protected file field here is opened.
///
/// What [showsInViewer] accepts goes to the in-app image viewer, alongside the
/// record's other such files; the viewer's URLs stay token-free because
/// `ProtectedFileCacheManager` appends the token at download time. Anything
/// else (a video, a PDF) is handed to the OS or the browser via `url_launcher`
/// with a file token: the app carries no video player or PDF viewer, and the
/// tokenised URL is good for about two minutes, which is ample for a launch.
Future<void> openProtectedAttachment(
  BuildContext context,
  WidgetRef ref, {
  required PbReadOnlyRepository<Object?> repo,
  required String recordId,
  required List<String> attachments,
  required String filename,
  required bool Function(String filename) showsInViewer,
}) async {
  if (showsInViewer(filename)) {
    final viewable = attachments.where(showsInViewer).toList();
    await showImageViewer(
      context,
      imageUrls: [
        for (final f in viewable) repo.fileUrl(recordId, f).toString(),
      ],
      initialIndex: viewable.indexOf(filename),
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
