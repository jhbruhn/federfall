import 'package:federfall/core/error/result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Result', () {
    test('Ok carries value', () {
      const r = Result<int>.ok(7);
      expect(r.isOk, isTrue);
      expect(r.valueOrNull, 7);
      expect(r.fold(ok: (v) => 'v$v', err: (_) => 'e'), 'v7');
    });

    test('Err carries error', () {
      final r = Result<int>.err(StateError('x'));
      expect(r.isErr, isTrue);
      expect(r.valueOrNull, isNull);
      expect(r.fold(ok: (_) => 'v', err: (e) => 'e'), 'e');
    });

    test('guard captures success', () async {
      final r = await Result.guard(() async => 42);
      expect(r, const Ok(42));
    });

    test('guard captures thrown error', () async {
      final r = await Result.guard<int>(() async => throw StateError('boom'));
      expect(r.isErr, isTrue);
      expect((r as Err<int>).error, isA<StateError>());
    });
  });
}
