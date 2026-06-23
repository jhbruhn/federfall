import 'dart:async';

import 'package:federfall/core/server/server_probe.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';

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
        return HealthCheck(code: 200);
      });

      expect(await probe.probe('https://'), isA<ProbeInvalidUrl>());
      expect(probed, isFalse);
    });

    test('healthy PocketBase (code 200) is reachable with normalised url',
        () async {
      final probe = ServerProbe((_) async => HealthCheck(code: 200));

      final result = await probe.probe('pigeons.example');

      expect(
        result,
        const ServerProbeResult.reachable('https://pigeons.example'),
      );
    });

    test('a non-200 health code is treated as not-Federfall', () async {
      final probe = ServerProbe((_) async => HealthCheck());

      expect(await probe.probe('pigeons.example'), isA<ProbeNotFederfall>());
    });

    test('a connection failure (statusCode 0) is unreachable', () async {
      final probe = ServerProbe(
        (_) async => throw ClientException(),
      );

      expect(await probe.probe('pigeons.example'), isA<ProbeUnreachable>());
    });

    test('an HTTP error response is not-Federfall', () async {
      final probe = ServerProbe(
        (_) async => throw ClientException(statusCode: 404),
      );

      expect(await probe.probe('pigeons.example'), isA<ProbeNotFederfall>());
    });

    test('a timeout is unreachable', () async {
      final probe = ServerProbe(
        (_) async => throw TimeoutException('slow'),
      );

      expect(await probe.probe('pigeons.example'), isA<ProbeUnreachable>());
    });
  });
}
