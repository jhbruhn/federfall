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

class _Thumb extends StatelessWidget {
  const _Thumb({required this.photo, required this.onRemove});

  final XFile photo;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: FutureBuilder<Uint8List>(
            future: photo.readAsBytes(),
            builder: (context, snap) {
              final bytes = snap.data;
              if (bytes == null) return const SizedBox(width: 88, height: 88);
              return Image.memory(
                bytes,
                width: 88,
                height: 88,
                fit: BoxFit.cover,
                errorBuilder: (context, _, _) => Container(
                  width: 88,
                  height: 88,
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: const Icon(Icons.image_outlined),
                ),
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
              onPressed: onRemove,
            ),
          ),
      ],
    );
  }
}
