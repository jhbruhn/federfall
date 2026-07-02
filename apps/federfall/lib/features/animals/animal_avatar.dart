import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/animals/animals_providers.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/features/cases/journal/journal_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

/// Round animal portrait for the detail headers (ctw.7). Shows the resolved
/// avatar image (the animal's own photo, else the latest case admission photo)
/// or a pets placeholder. When [editable], tapping opens the set/replace/remove
/// flow — reachable from both the animal lifetime header and the case header.
class AnimalAvatar extends ConsumerWidget {
  const AnimalAvatar({
    required this.animalId,
    this.radius = 28,
    this.editable = false,
    super.key,
  });

  final String animalId;

  /// Circle radius in logical pixels.
  final double radius;

  /// Whether tapping opens the photo set/replace/remove flow.
  final bool editable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final url = ref.watch(animalAvatarUrlProvider(animalId)).value;
    final diameter = radius * 2;

    final placeholder = Icon(
      Icons.pets,
      size: radius,
      color: colors.onSurfaceVariant,
    );

    final avatar = CircleAvatar(
      radius: radius,
      backgroundColor: colors.surfaceContainerHighest,
      child: ClipOval(
        child: url == null
            ? placeholder
            : CachedFileImage(
                url: url,
                width: diameter,
                height: diameter,
                errorWidget: placeholder,
              ),
      ),
    );

    if (!editable) return avatar;
    return InkWell(
      onTap: () => _editPhoto(context, ref),
      customBorder: const CircleBorder(),
      child: avatar,
    );
  }

  Future<void> _editPhoto(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final animal = ref.read(animalByIdProvider(animalId)).value;
    final hasPhoto = animal?.photo != null && animal!.photo!.isNotEmpty;
    // Everything ref-dependent is captured before the awaits: the camera flow
    // can dispose this element (Android backgrounds the activity), and ref
    // must not be touched afterwards.
    final picker = ref.read(imagePickerProvider);
    final repo = await ref.read(animalsRepositoryProvider.future);
    if (!context.mounted) return;

    final action = await showModalBottomSheet<_PhotoAction>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(l10n.animalPhotoGallery),
              onTap: () => Navigator.pop(context, _PhotoAction.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(l10n.photoCaptureAction),
              onTap: () => Navigator.pop(context, _PhotoAction.camera),
            ),
            if (hasPhoto)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: Text(l10n.animalPhotoRemove),
                onTap: () => Navigator.pop(context, _PhotoAction.remove),
              ),
          ],
        ),
      ),
    );
    if (action == null) return;

    try {
      switch (action) {
        case _PhotoAction.remove:
          await repo.update(animalId, {'photo': null});
        case _PhotoAction.gallery:
        case _PhotoAction.camera:
          final shot = await picker.pickImage(
            source: action == _PhotoAction.camera
                ? ImageSource.camera
                : ImageSource.gallery,
          );
          if (shot == null) return;
          final name = shot.name.isEmpty ? 'animal_photo.jpg' : shot.name;
          await repo.updateWithFiles(animalId, const {}, [
            http.MultipartFile.fromBytes(
              'photo',
              await shot.readAsBytes(),
              filename: name,
            ),
          ]);
      }
    } on RepositoryException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(errorMessage(l10n, e))));
      return;
    } on Object catch (e, stackTrace) {
      reportCaughtError(e, stackTrace);
      messenger.showSnackBar(SnackBar(content: Text(errorMessage(l10n, e))));
      return;
    }

    if (!context.mounted) return;
    ref
      ..invalidate(animalByIdProvider(animalId))
      ..invalidate(animalAvatarUrlProvider(animalId))
      ..invalidate(animalLifetimeProvider(animalId))
      ..invalidate(animalsRegistryProvider);
  }
}

enum _PhotoAction { gallery, camera, remove }
