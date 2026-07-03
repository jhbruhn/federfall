import 'dart:async';

import 'package:federfall/core/server/server_probe.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';

/// A minimal valid `/api/federfall/info` body.
Map<String, Object?> _infoBody({
  String name = 'Federfall',
  bool passwordReset = false,
}) => {
  'service': 'federfall',
  'federfall': true,
  'version': '1.0.0',
  'name': name,
  'auth': {
    'password': true,
    'oauth2': <String>[],
    'passwordReset': passwordReset,
    'selfSignup': false,
  },
};

void main() {
  group('normalizeServerUrl', () {
    test('assumes https when no scheme is given', () {
      expect(normalizeServerUrl('pigeons.example'), 'https://pigeons.example');
    });

    test('keeps an explicit http scheme and port (local dev)', () {
      expect(
        normalizeServerUrl('http://localhost:8090'),
        'http://localhost:8090',
      );
    });

    test('assumes https for a scheme-less host:port', () {
      expect(
        normalizeServerUrl('192.168.1.5:8090'),
        'https://192.168.1.5:8090',
      );
    });

    test('trims whitespace and strips trailing slashes', () {
      expect(
        normalizeServerUrl('  https://pigeons.example/  '),
        'https://pigeons.example',
      );
    });

    test('preserves a sub-path but drops query and fragment', () {
      expect(
        normalizeServerUrl('https://host.example/federfall/?x=1#frag'),
        'https://host.example/federfall',
      );
    });

    test('rejects empty, schemeless-hostless and non-http(s) input', () {
      expect(normalizeServerUrl(''), isNull);
      expect(normalizeServerUrl('   '), isNull);
      expect(normalizeServerUrl('ftp://host.example'), isNull);
      expect(normalizeServerUrl('https://'), isNull);
    });
  });

  group('ServerProbe.probe', () {
    test('invalid URL is reported without probing', () async {
      var probed = false;
      final probe = ServerProbe((_) async {
        probed = true;
        return _infoBody();
      });

      expect(await probe.probe('https://'), isA<ProbeInvalidUrl>());
      expect(probed, isFalse);
    });

    test(
      'a Federfall server is reachable with its normalised url + info',
      () async {
        final probe = ServerProbe(
          (_) async => _infoBody(name: 'Wildvogelhilfe', passwordReset: true),
        );

        final result = await probe.probe('pigeons.example');

        expect(result, isA<ProbeReachable>());
        final reachable = result as ProbeReachable;
        expect(reachable.baseUrl, 'https://pigeons.example');
        expect(reachable.info.name, 'Wildvogelhilfe');
        expect(reachable.info.auth.passwordReset, isTrue);
      },
    );

    test(
      'a generic PocketBase (no marker in a 200 body) is not-Federfall',
      () async {
        final probe = ServerProbe((_) async => {'message': 'ok'});

        expect(await probe.probe('pigeons.example'), isA<ProbeNotFederfall>());
      },
    );

    test('a connection failure (statusCode 0) is unreachable', () async {
      final probe = ServerProbe(
        (_) async => throw ClientException(),
      );

      expect(await probe.probe('pigeons.example'), isA<ProbeUnreachable>());
    });

    test(
      'a 404 (route missing on a generic PocketBase) is not-Federfall',
      () async {
        final probe = ServerProbe(
          (_) async => throw ClientException(statusCode: 404),
        );

        expect(await probe.probe('pigeons.example'), isA<ProbeNotFederfall>());
      },
    );

    test('a timeout is unreachable', () async {
      final probe = ServerProbe(
        (_) async => throw TimeoutException('slow'),
      );

      expect(await probe.probe('pigeons.example'), isA<ProbeUnreachable>());
    });

    test(
      'explicit http:// on a non-loopback host is rejected unprobed',
      () async {
        var probed = false;
        final probe = ServerProbe((_) async {
          probed = true;
          return _infoBody();
        });

        expect(
          await probe.probe('http://pigeons.example'),
          isA<ProbeInsecureHttp>(),
        );
        expect(probed, isFalse);
      },
    );

    test(
      'explicit http:// on localhost is still probed (dev escape hatch)',
      () async {
        final probe = ServerProbe((_) async => _infoBody());

        final result = await probe.probe('http://localhost:8090');

        expect(result, isA<ProbeReachable>());
        expect((result as ProbeReachable).baseUrl, 'http://localhost:8090');
      },
    );

    test(
      'explicit http:// on 127.0.0.1 is still probed (dev escape hatch)',
      () async {
        final probe = ServerProbe((_) async => _infoBody());

        expect(
          await probe.probe('http://127.0.0.1:8090'),
          isA<ProbeReachable>(),
        );
      },
    );
  });
}
