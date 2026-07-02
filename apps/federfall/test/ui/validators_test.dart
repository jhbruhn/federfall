import 'package:federfall/l10n/gen/app_localizations.dart';
import 'package:federfall/ui/validators.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('de'));

  group('required', () {
    final v = Validators.required(l10n);
    test('rejects empty/whitespace', () {
      expect(v(null), isNotNull);
      expect(v('  '), isNotNull);
    });
    test('accepts text', () => expect(v('x'), isNull));
  });

  group('url', () {
    final v = Validators.url(l10n);
    test('accepts http(s) URLs', () {
      expect(v('https://pigeons.example'), isNull);
      expect(v('http://localhost:8090'), isNull);
    });
    test('empty passes (compose with required)', () => expect(v(''), isNull));
    test('rejects malformed / non-http', () {
      expect(v('not a url'), isNotNull);
      expect(v('ftp://x.example'), isNotNull);
    });
  });

  group('email', () {
    final v = Validators.email(l10n);
    test('accepts plausible address', () => expect(v('a@b.de'), isNull));
    test('rejects malformed', () => expect(v('a@b'), isNotNull));
  });

  group('minLength', () {
    final v = Validators.minLength(l10n, 8);
    test('rejects a short value', () => expect(v('1234567'), isNotNull));
    test('accepts at the boundary', () => expect(v('12345678'), isNull));
    test('empty passes (compose with required)', () => expect(v(''), isNull));
    test('does not trim', () => expect(v('  pass  '), isNull));
  });

  group('compose', () {
    test('returns first failure in order', () {
      final v = Validators.compose([
        Validators.required(l10n),
        Validators.url(l10n),
      ]);
      expect(v(''), l10n.fieldRequired);
      expect(v('bad'), l10n.fieldInvalidUrl);
      expect(v('https://ok.example'), isNull);
    });
  });
}
