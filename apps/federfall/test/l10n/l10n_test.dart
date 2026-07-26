import 'package:federfall/l10n/l10n.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveAppLocale', () {
    test('follows the device language when we ship it', () {
      expect(resolveAppLocale([const Locale('en')]), const Locale('en'));
      expect(resolveAppLocale([const Locale('de')]), const Locale('de'));
    });

    test('matches on language code, ignoring the region', () {
      expect(
        resolveAppLocale([const Locale('de', 'AT')]),
        const Locale('de'),
      );
      expect(
        resolveAppLocale([const Locale('en', 'US')]),
        const Locale('en'),
      );
    });

    test('honours the device preference order', () {
      // A device set to French first, English second, gets English — not the
      // German fallback: a shipped language further down the list still wins.
      expect(
        resolveAppLocale([
          const Locale('fr'),
          const Locale('en'),
          const Locale('de'),
        ]),
        const Locale('en'),
      );
    });

    test('falls back to German for a language we do not ship', () {
      expect(resolveAppLocale([const Locale('fr')]), kFallbackLocale);
      expect(kFallbackLocale, const Locale('de'));
    });

    test('falls back to German with no device preference at all', () {
      expect(resolveAppLocale(null), kFallbackLocale);
      expect(resolveAppLocale([]), kFallbackLocale);
    });
  });
}
