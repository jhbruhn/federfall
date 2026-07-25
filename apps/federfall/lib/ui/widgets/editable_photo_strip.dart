import 'package:federfall/theme/app_spacing.dart';
import 'package:federfall/ui/widgets/cached_file_image.dart';
import 'package:federfall/ui/widgets/staged_photos.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// The photos staged for a record being EDITED: the ones already stored on the
/// server first (network thumbnails), then the newly picked local ones. Each is
/// removable — dropping an existing filename is what makes a save delete it,
/// since the survivors are sent as the field's new value.
///
/// [StagedPhotos] covers the create-only case (local photos plus the pick
/// actions); this covers a form that must also show and prune what is already
/// uploaded. The pick actions stay with the caller, whose labels name the
/// record kind.
class EditablePhotoStrip extends StatelessWidget {
  const EditablePhotoStrip({
    required this.existing,
    required this.newPhotos,
    required this.thumbUrl,
    required this.onRemoveExisting,
    required this.onRemoveNew,
    this.size = 88,
    super.key,
  });

  /// Filenames still stored on the record.
  final List<String> existing;

  /// Freshly picked photos, not yet uploaded.
  final List<XFile> newPhotos;

  /// Resolves the thumbnail URL for a stored filename. `null` while the
  /// repository (or the record id) isn't available yet — the existing photos
  /// then hold their space instead of flashing an error tile.
  final Uri Function(String filename)? thumbUrl;

  final ValueChanged<int>? onRemoveExisting;
  final ValueChanged<int>? onRemoveNew;
  final double size;

  @override
  Widget build(BuildContext context) {
    final resolve = thumbUrl;

    return SizedBox(
      height: size,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          // Keys on both loops: removing photo i must not remount (and
          // re-fetch / re-read) every thumbnail after it.
          for (var i = 0; i < existing.length; i++)
            Padding(
              key: ValueKey(existing[i]),
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: _Thumb(
                onRemove: onRemoveExisting == null
                    ? null
                    : () => onRemoveExisting!(i),
                child: resolve == null
                    ? SizedBox(width: size, height: size)
                    : CachedFileImage(
                        url: resolve(existing[i]),
                        width: size,
                        height: size,
                      ),
              ),
            ),
          for (var i = 0; i < newPhotos.length; i++)
            Padding(
              key: ObjectKey(newPhotos[i]),
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: _Thumb(
                onRemove: onRemoveNew == null ? null : () => onRemoveNew!(i),
                child: LocalPhotoThumb(photo: newPhotos[i], size: size),
              ),
            ),
        ],
      ),
    );
  }
}

/// A rounded thumbnail with an optional remove badge.
class _Thumb extends StatelessWidget {
  const _Thumb({required this.child, this.onRemove});

  final Widget child;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(borderRadius: BorderRadius.circular(8), child: child),
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
