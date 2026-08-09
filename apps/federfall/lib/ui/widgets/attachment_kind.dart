import 'package:flutter/material.dart';

/// The video extensions the server accepts (`video/mp4`, `video/quicktime`,
/// `video/webm` in migration 1700000073), plus the aliases those MIME types
/// are written with in practice.
const Set<String> _videoExtensions = {
  'mp4',
  'm4v',
  'mov',
  'qt',
  'webm',
};

/// Whether [nameOrPath] names a video rather than an image.
///
/// Every place that would draw a thumbnail has to ask this first, for two
/// separate reasons:
///
///  * PocketBase generates a `?thumb=WxH` variant for **images only**; for
///    anything else it silently serves the ORIGINAL (the 1700000049 finding).
///    Requesting a thumbnail of a 50 MB `.mp4` therefore downloads 50 MB to
///    paint an 88 px tile.
///  * `Image.memory` on a picked local video throws — it is not an image, and
///    the staging strips decode what they were handed.
///
/// Decided by extension because that is all a stored filename carries; a
/// picked `XFile` has a name (or, in tests, only a path), never a MIME type
/// that survives the round trip.
bool isVideoAttachment(String nameOrPath) {
  final dot = nameOrPath.lastIndexOf('.');
  if (dot < 0 || dot == nameOrPath.length - 1) return false;
  return _videoExtensions.contains(nameOrPath.substring(dot + 1).toLowerCase());
}

/// The square stand-in a video attachment gets instead of a thumbnail —
/// see [isVideoAttachment] for why there is no picture to show.
class VideoAttachmentThumb extends StatelessWidget {
  const VideoAttachmentThumb({this.size = 88, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      color: scheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(
        Icons.play_circle_outline,
        size: size / 2.5,
        color: scheme.onSurfaceVariant,
      ),
    );
  }
}
