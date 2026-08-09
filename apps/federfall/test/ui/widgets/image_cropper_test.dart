import 'dart:typed_data';

import 'package:federfall/ui/ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// A [width]x[height] block of raw RGBA, as `ui.Image.toByteData` produces:
/// the left half red, the right half blue, so a re-encode can be checked by
/// reading a pixel back rather than by size alone.
Uint8List _twoToneRgba(int width, int height) {
  final rgba = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      final left = x < width / 2;
      rgba[i] = left ? 255 : 0;
      rgba[i + 2] = left ? 0 : 255;
      rgba[i + 3] = 255;
    }
  }
  return rgba;
}

void main() {
  group('encodeRgbaAsJpeg', () {
    test('produces JPEG bytes of the given dimensions', () {
      final jpeg = encodeRgbaAsJpeg((
        rgba: _twoToneRgba(64, 32),
        width: 64,
        height: 32,
      ));

      // SOI marker — the bytes really are JPEG, not just decodable.
      expect(jpeg.take(2), [0xFF, 0xD8]);
      final decoded = img.decodeJpg(jpeg)!;
      expect(decoded.width, 64);
      expect(decoded.height, 32);
    });

    test('round-trips through decodeImage', () {
      final out = img.decodeImage(
        encodeRgbaAsJpeg((rgba: _twoToneRgba(64, 32), width: 64, height: 32)),
      )!;

      expect(out.width, 64);
      expect(out.height, 32);
    });

    test('preserves the pixels it was handed', () {
      final out = img.decodeImage(
        encodeRgbaAsJpeg((rgba: _twoToneRgba(80, 40), width: 80, height: 40)),
      )!;

      // JPEG is lossy, so assert the dominant channel per half, not exact
      // triples.
      final left = out.getPixel(10, 20);
      final right = out.getPixel(70, 20);
      expect(left.r, greaterThan(left.b));
      expect(right.b, greaterThan(right.r));
    });

    test('is smaller than the raw pixels it came from', () {
      final rgba = _twoToneRgba(400, 400);
      final jpeg = encodeRgbaAsJpeg((rgba: rgba, width: 400, height: 400));

      expect(jpeg.length, lessThan(rgba.length));
    });
  });
}
