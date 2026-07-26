import 'dart:typed_data';

import 'package:federfall/features/cases/case_intake_draft_store.dart';
import 'package:image_picker/image_picker.dart';

/// [StagedPhotoLoader] that answers from a map instead of the filesystem —
/// real file I/O never progresses inside a widget test's async zone.
///
/// Paths absent from [available] load as `null`, standing in for a photo the OS
/// has evicted from the picker's cache directory since the draft was written.
class FakeStagedPhotoLoader extends StagedPhotoLoader {
  FakeStagedPhotoLoader(this.available);

  /// Paths that still resolve, mapped to the name their file should carry.
  final Map<String, String> available;

  @override
  Future<XFile?> load(String path) async {
    final name = available[path];
    if (name == null) return null;
    return XFile.fromData(
      Uint8List.fromList([1, 2, 3]),
      name: name,
      mimeType: 'image/jpeg',
    );
  }
}
