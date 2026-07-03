import 'package:federfall/core/logging/app_logger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('scrubLogPayload', () {
    test('redacts a protected-file token query param', () {
      const url =
          'https://pb.example/api/files/cases/1/x.png?token=abc123.def456';
      final out = scrubLogPayload('ClientException: {url: $url, status: 0}');
      expect(out, isNot(contains('abc123')));
      expect(out, contains('token=***'));
    });

    test('redacts an Authorization bearer header', () {
      final out = scrubLogPayload('Authorization: Bearer eyJhbGciOiJIUzI1');
      expect(out, isNot(contains('eyJhbGciOiJIUzI1')));
      expect(out, contains('Bearer ***'));
    });

    test('redacts PII field values in a Dart map toString body', () {
      final out = scrubLogPayload(
        '{response: {data: {phone: {code: validation_invalid, '
        'message: "must be a valid phone: +49 151 2345678"}, '
        'email: finder@example.org}}}',
      );
      expect(out, isNot(contains('+49 151 2345678')));
      expect(out, isNot(contains('finder@example.org')));
    });

    test('redacts PII field values in a JSON-shaped body', () {
      final out = scrubLogPayload(
        '{"first_name":"Maria","last_name":"Muster","notes":"lives nearby"}',
      );
      expect(out, isNot(contains('Maria')));
      expect(out, isNot(contains('Muster')));
      expect(out, isNot(contains('lives nearby')));
    });

    test('leaves unrelated text untouched', () {
      const text = 'Could not reach the server';
      expect(scrubLogPayload(text), text);
    });
  });
}
