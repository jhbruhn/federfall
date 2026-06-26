import 'package:federfall/core/server/server_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ServerInfo.tryParse', () {
    test('parses a full Federfall payload', () {
      final info = ServerInfo.tryParse({
        'service': 'federfall',
        'federfall': true,
        'version': '1.2.0',
        'minClient': '1.0.0',
        'name': 'Wildvogelhilfe',
        'auth': {
          'password': true,
          'oauth2': ['google', 'github'],
          'passwordReset': true,
          'selfSignup': false,
        },
      });

      expect(info, isNotNull);
      expect(info!.version, '1.2.0');
      expect(info.minClient, '1.0.0');
      expect(info.name, 'Wildvogelhilfe');
      expect(info.auth.password, isTrue);
      expect(info.auth.oauth2, ['google', 'github']);
      expect(info.auth.passwordReset, isTrue);
      expect(info.auth.selfSignup, isFalse);
    });

    test('accepts the federfall marker alone and fills defaults', () {
      final info = ServerInfo.tryParse({'federfall': true});

      expect(info, isNotNull);
      expect(info!.name, 'Federfall');
      expect(info.auth.password, isTrue);
      expect(info.auth.oauth2, isEmpty);
      expect(info.auth.passwordReset, isFalse);
    });

    test('rejects a body without the marker (generic PocketBase)', () {
      expect(ServerInfo.tryParse({'message': 'ok', 'code': 200}), isNull);
    });

    test('rejects non-map input', () {
      expect(ServerInfo.tryParse(null), isNull);
      expect(ServerInfo.tryParse('federfall'), isNull);
      expect(ServerInfo.tryParse(42), isNull);
    });

    test('tolerates a malformed auth block', () {
      final info = ServerInfo.tryParse({
        'federfall': true,
        'auth': 'nonsense',
      });

      expect(info, isNotNull);
      expect(info!.auth.password, isTrue);
    });
  });
}
