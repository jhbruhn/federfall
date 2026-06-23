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
}
