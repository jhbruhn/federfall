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

    test('maps a malformed date to null instead of throwing', () {
      expect(pbDate('not-a-date'), isNull);
      expect(pbDate('12.03.2026'), isNull);
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
      // Zero is a reading, not an absence, for a plain number.
      expect(pbDouble(0), 0);
    });
  });

  group('pbQuantity', () {
    test('treats zero as absent, since PocketBase has no null number', () {
      // Clearing a number field stores 0 and the API returns 0, so a dose or a
      // rate of "0" is how "not prescribed" arrives.
      expect(pbQuantity(0), isNull);
      expect(pbQuantity(0.0), isNull);
      expect(pbQuantity('0'), isNull);
      expect(pbQuantity(''), isNull);
      expect(pbQuantity(null), isNull);
    });

    test('passes real quantities through, including small ones', () {
      expect(pbQuantity(20), 20);
      expect(pbQuantity(0.001), 0.001);
      expect(pbQuantity('1.5'), 1.5);
    });
  });

  group('pbCount', () {
    test('treats zero as absent, like pbQuantity does for a rate', () {
      // The bug this exists for: an unset `cycle_off_days` arrives as 0, which
      // is not null, so a prescription with no rhythm read as "0 days on, 0
      // days off" and the form opened with the cycle switched ON over two
      // zeroes it then refused to save.
      expect(pbCount(0), isNull);
      expect(pbCount('0'), isNull);
      expect(pbCount(''), isNull);
      expect(pbCount(null), isNull);
    });

    test('passes real counts through', () {
      expect(pbCount(1), 1);
      expect(pbCount(5), 5);
      expect(pbCount('24'), 24);
    });

    test('pbInt still reports a zero, for the counts that mean it', () {
      // A case count of 0 is a fact about an org, not a missing value.
      expect(pbInt(0), 0);
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
      expect(
        CaseStatus.fromWire('ready_for_release'),
        CaseStatus.readyForRelease,
      );
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
