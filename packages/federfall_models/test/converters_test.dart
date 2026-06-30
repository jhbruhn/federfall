import 'package:federfall_models/federfall_models.dart';
import 'package:test/test.dart';

void main() {
  group('pbDate', () {
    test('parses space-separated PocketBase datetime as UTC', () {
      final d = pbDate('2026-03-10 09:00:00.000Z');
      expect(d, isNotNull);
      expect(d!.isUtc, isTrue);
      expect(d.year, 2026);
      expect(d.month, 3);
      expect(d.day, 10);
      expect(d.hour, 9);
    });

    test('maps empty / null to null', () {
      expect(pbDate(''), isNull);
      expect(pbDate(null), isNull);
    });
  });

  group('pbString', () {
    test('empty string becomes null', () => expect(pbString(''), isNull));
    test('passes through non-empty', () => expect(pbString('x'), 'x'));
  });

  group('pbInt / pbDouble', () {
    test('reads numbers and string-encoded numbers', () {
      expect(pbInt(5), 5);
      expect(pbInt('5'), 5);
      expect(pbDouble(1.5), 1.5);
      expect(pbDouble(''), isNull);
    });
  });

  group('pbStringList', () {
    test('filters empties, tolerates scalar and null', () {
      expect(pbStringList(['a', '', 'b']), ['a', 'b']);
      expect(pbStringList('a'), ['a']);
      expect(pbStringList(null), isEmpty);
    });
  });

  group('enums', () {
    test('round-trip wire values', () {
      expect(UserRole.fromWire('coordinator'), UserRole.coordinator);
      expect(CaseStatus.fromWire('ready_for_release'),
          CaseStatus.readyForRelease);
      expect(DispositionType.placedInAviary.wire, 'placed_in_aviary');
    });

    test('unknown / empty wire is null', () {
      expect(Sex.fromWire('nope'), isNull);
      expect(Sex.fromWire(''), isNull);
    });

    test('multi-select skips unknowns', () {
      expect(
        pbEnumList(
          Sex.values,
          (e) => e.wire,
          ['male', 'bogus', 'unknown'],
        ),
        [Sex.male, Sex.unknown],
      );
    });
  });
}
