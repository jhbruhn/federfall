import 'dart:typed_data';

import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// A photo-staging control: a horizontal strip of removable local-photo
/// thumbnails plus "add from gallery" / "take photo" actions. The parent owns
/// the [photos] list and the picking (so it can inject the picker for tests).
class StagedPhotos extends StatelessWidget {
  const StagedPhotos({
    required this.photos,
    required this.enabled,
    required this.onAdd,
    required this.onCapture,
    required this.onRemove,
    super.key,
  });

  final List<XFile> photos;
  final bool enabled;
  final VoidCallback onAdd;
  final VoidCallback onCapture;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (photos.isNotEmpty)
          SizedBox(
            height: 88,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: photos.length,
              separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
              itemBuilder: (context, i) => _Thumb(
                // Keyed by the file so removing photo i doesn't remount (and
                // re-read) every thumbnail after it.
                key: ObjectKey(photos[i]),
                photo: photos[i],
                onRemove: enabled ? () => onRemove(i) : null,
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            OutlinedButton.icon(
              onPressed: enabled ? onAdd : null,
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(l10n.photoAddAction),
            ),
            OutlinedButton.icon(
              onPressed: enabled ? onCapture : null,
              icon: const Icon(Icons.photo_camera_outlined),
              label: Text(l10n.photoCaptureAction),
            ),
          ],
        ),
      ],
    );
  }
}

/// A square thumbnail of a not-yet-uploaded local photo. Reads the file's
/// bytes once per file (cached across parent rebuilds — a form keystroke must
/// not hit the disk) and decodes at thumbnail resolution via `cacheWidth`
/// instead of holding the full-resolution frame in memory.
class LocalPhotoThumb extends StatefulWidget {
  const LocalPhotoThumb({required this.photo, this.size = 88, super.key});

  final XFile photo;
  final double size;

  @override
  State<LocalPhotoThumb> createState() => _LocalPhotoThumbState();
}

class _LocalPhotoThumbState extends State<LocalPhotoThumb> {
  late Future<Uint8List> _bytes;

  @override
  void initState() {
    super.initState();
    _bytes = widget.photo.readAsBytes();
  }

  @override
  void didUpdateWidget(LocalPhotoThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photo.path != widget.photo.path) {
      _bytes = widget.photo.readAsBytes();
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return FutureBuilder<Uint8List>(
      future: _bytes,
      builder: (context, snap) {
        final bytes = snap.data;
        if (bytes == null) return SizedBox(width: size, height: size);
        return Image.memory(
          bytes,
          width: size,
          height: size,
          fit: BoxFit.cover,
          cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
          errorBuilder: (context, _, _) => Container(
            width: size,
            height: size,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Icon(Icons.image_outlined),
          ),
        );
      },
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.photo, required this.onRemove, super.key});

  final XFile photo;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LocalPhotoThumb(photo: photo),
        ),
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
