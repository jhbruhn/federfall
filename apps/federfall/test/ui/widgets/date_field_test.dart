import 'package:federfall/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Resolve the real MaterialLocalizations for a known locale so the formatted
  // strings are deterministic.
  late MaterialLocalizations m;

  setUp(() async {
    m = await GlobalMaterialLocalizations.delegate.load(const Locale('en'));
  });

  group('formatEventDate', () {
    test('returns empty string for null', () {
      expect(formatEventDate(m, null), '');
    });

    test('converts a UTC timestamp to local time before formatting', () {
      // PocketBase stores UTC; the displayed date must be the local one.
      final utc = DateTime.utc(2026, 3, 4, 9, 30);
      final local = utc.toLocal();

      expect(
        formatEventDate(m, utc),
        m.formatMediumDate(local),
      );
      expect(
        formatEventDate(m, utc, withTime: true),
        '${m.formatMediumDate(local)}, '
        '${m.formatTimeOfDay(TimeOfDay.fromDateTime(local))}',
      );
    });
  });
}
