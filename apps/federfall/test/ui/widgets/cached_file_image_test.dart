import 'package:federfall/ui/widgets/cached_file_image.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('fileCacheKey', () {
    test('strips the token so a rotated token maps to the same key', () {
      final a = Uri.parse(
        'https://pb.example.org/api/files/animals/r1/p.jpg?token=AAA',
      );
      final b = Uri.parse(
        'https://pb.example.org/api/files/animals/r1/p.jpg?token=BBB',
      );
      expect(fileCacheKey(a), fileCacheKey(b));
      expect(fileCacheKey(a), isNot(contains('token')));
      expect(
        fileCacheKey(a),
        'https://pb.example.org/api/files/animals/r1/p.jpg',
      );
    });

    test('keeps the thumb param (distinct cache entry) but drops token', () {
      final url = Uri.parse(
        'https://pb.example.org/api/files/cases/c1/x.jpg'
        '?thumb=200x200&token=AAA',
      );
      final key = fileCacheKey(url);
      expect(key, contains('thumb=200x200'));
      expect(key, isNot(contains('token')));
    });

    test('a token-free URL is returned unchanged', () {
      const raw = 'https://pb.example.org/api/files/cases/c1/x.jpg';
      expect(fileCacheKey(Uri.parse(raw)), raw);
    });
  });
}
