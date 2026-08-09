import 'package:federfall/ui/ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isVideoAttachment', () {
    test('recognises every video type the server accepts', () {
      // The `mimeTypes` allowlist on microscopy_samples.attachments
      // (1700000073): video/mp4, video/quicktime, video/webm.
      for (final name in ['clip.mp4', 'clip.m4v', 'clip.mov', 'clip.webm']) {
        expect(isVideoAttachment(name), isTrue, reason: name);
      }
    });

    test('an image is not one, whatever its case', () {
      for (final name in ['smear.jpg', 'smear.PNG', 'a.webp', 'a.gif']) {
        expect(isVideoAttachment(name), isFalse, reason: name);
      }
    });

    test('an extension is matched case-insensitively', () {
      // A phone hands over MOV, and PocketBase stores the name it was given.
      expect(isVideoAttachment('IMG_0042.MOV'), isTrue);
    });

    test('a name with no extension is not a video', () {
      // The failure mode this protects: `Image.memory` on a video throws, and
      // guessing "video" for an unknown name would hide a real image instead.
      expect(isVideoAttachment('noextension'), isFalse);
      expect(isVideoAttachment('trailing.'), isFalse);
      expect(isVideoAttachment(''), isFalse);
    });

    test('a full path works as well as a bare filename', () {
      // XFile.name can be empty in tests, so callers fall back to the path.
      expect(isVideoAttachment('/tmp/picker/1234.mp4'), isTrue);
    });
  });
}
