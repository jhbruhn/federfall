import 'package:federfall_data/federfall_data.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:test/test.dart';

void main() {
  group('RepositoryException.fromClient', () {
    RepositoryException of(int status) =>
        RepositoryException.fromClient(ClientException(statusCode: status));

    test('classifies by status code', () {
      expect(of(0).kind, RepositoryErrorKind.network);
      expect(of(0).isNetwork, isTrue);
      expect(of(401).kind, RepositoryErrorKind.unauthorized);
      expect(of(403).kind, RepositoryErrorKind.unauthorized);
      expect(of(404).kind, RepositoryErrorKind.notFound);
      expect(of(400).kind, RepositoryErrorKind.validation);
      expect(of(422).kind, RepositoryErrorKind.validation);
      expect(of(500).kind, RepositoryErrorKind.unknown);
    });

    test('preserves status and cause', () {
      final e = of(404);
      expect(e.statusCode, 404);
      expect(e.cause, isA<ClientException>());
    });
  });

  group('idempotentWriteException (federfall-lebw)', () {
    RepositoryException of(int status) =>
        idempotentWriteException(ClientException(statusCode: status));

    test('a 409 is the key-reused refusal, whatever its data says', () {
      final e = of(409);
      expect(e.statusCode, 409);
      expect(e.kind, RepositoryErrorKind.validation);
      expect(e.serverCodes, [idempotencyKeyReusedCode]);
      expect(e.cause, isA<ClientException>());
      expect(isIdempotencyKeyReused(e), isTrue);
    });

    test('everything else is translated exactly as fromClient does', () {
      for (final status in [0, 400, 403, 404, 500]) {
        final e = of(status);
        expect(
          e.kind,
          RepositoryException.fromClient(
            ClientException(statusCode: status),
          ).kind,
        );
        expect(isIdempotencyKeyReused(e), isFalse);
      }
    });

    test('isIdempotencyKeyReused is false for anything else', () {
      expect(isIdempotencyKeyReused(Exception('x')), isFalse);
      expect(isIdempotencyKeyReused(const RepositoryException('x')), isFalse);
    });
  });
}
