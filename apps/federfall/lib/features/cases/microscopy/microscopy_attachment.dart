import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens one attachment of microscopy sample [sampleId]: an image in the
/// in-app viewer, a video externally (federfall-ewcf tracks an inline player,
/// and records that `web_headers.pb.js` has no `media-src` directive today).
Future<void> openMicroscopyAttachment(
  BuildContext context,
  WidgetRef ref, {
  required String sampleId,
  required List<String> attachments,
  required int index,
}) async {
  final repo = await ref.read(microscopySamplesRepositoryProvider.future);
  if (!context.mounted) return;
  await openProtectedAttachment(
    context,
    ref,
    repo: repo,
    recordId: sampleId,
    attachments: attachments,
    filename: attachments[index],
    showsInViewer: (f) => !isVideoAttachment(f),
  );
}
