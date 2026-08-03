import 'package:federfall/config/app_environment.dart';
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
      expect(info.auth.oauth2Scopes, isEmpty);
      expect(info.auth.passwordReset, isFalse);
    });

    test('parses per-provider OAuth2 scope overrides', () {
      final info = ServerInfo.tryParse({
        'federfall': true,
        'auth': {
          'oauth2': ['oidc'],
          'oauth2Scopes': {
            'oidc': ['openid', 'email', 'profile', 'groups'],
          },
        },
      });

      expect(info!.auth.oauth2Scopes['oidc'], [
        'openid',
        'email',
        'profile',
        'groups',
      ]);
    });

    test('ignores a malformed oauth2Scopes value', () {
      // A server sending the wrong shape must not break discovery — the app
      // just falls back to PocketBase's own scopes.
      final info = ServerInfo.tryParse({
        'federfall': true,
        'auth': {
          'oauth2Scopes': {'oidc': 'openid email', 'ok': <String>[]},
        },
      });

      expect(info!.auth.oauth2Scopes.containsKey('oidc'), isFalse);
      expect(info.auth.oauth2Scopes['ok'], isEmpty);
    });

    test('an older server omitting oauth2Scopes yields an empty map', () {
      final info = ServerInfo.tryParse({
        'federfall': true,
        'auth': {
          'oauth2': ['oidc'],
        },
      });

      expect(info!.auth.oauth2Scopes, isEmpty);
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

  group('ServerInfo.tryParse map block', () {
    ServerMapConfig? parseMap(Object? map) =>
        ServerInfo.tryParse({'federfall': true, 'map': map})?.map;

    test('is null when the server prescribes nothing', () {
      expect(ServerInfo.tryParse({'federfall': true})?.map, isNull);
    });

    test('parses a raster prescription', () {
      final map = parseMap({
        'mode': 'raster',
        'tileUrl': 'https://tiles.example.org/{z}/{x}/{y}.png',
        'attribution': '© Example Tiles',
        'attributionUrl': 'https://example.org/licence',
      });

      expect(map, isNotNull);
      expect(map!.mode, MapMode.raster);
      expect(map.url, 'https://tiles.example.org/{z}/{x}/{y}.png');
      expect(map.attribution, '© Example Tiles');
      expect(map.attributionUrl, 'https://example.org/licence');
    });

    test('parses a vector prescription without an attribution link', () {
      final map = parseMap({
        'mode': 'vector',
        'styleUrl': 'https://maps.example.org/style.json',
        'attribution': '© Example',
      });

      expect(map, isNotNull);
      expect(map!.mode, MapMode.vector);
      expect(map.url, 'https://maps.example.org/style.json');
      expect(map.attributionUrl, isNull);
    });

    test('carries the provider API key when one is configured', () {
      final map = parseMap({
        'mode': 'vector',
        'styleUrl': 'https://api.example.org/style.json?key={key}',
        'attribution': '© Example',
        'apiKey': 'abc123',
      });

      expect(map!.apiKey, 'abc123');
      // Left unsubstituted here: the vector path needs the raw token so the
      // style reader can also reach the URLs inside the style.
      expect(map.url, 'https://api.example.org/style.json?key={key}');
    });

    test('a blank API key is the same as none', () {
      final map = parseMap({
        'mode': 'vector',
        'styleUrl': 'https://x.org/s.json',
        'attribution': '© X',
        'apiKey': '',
      });

      expect(map!.apiKey, isNull);
    });

    test('reads only the URL belonging to the mode', () {
      final map = parseMap({
        'mode': 'raster',
        'styleUrl': 'https://maps.example.org/style.json',
        'tileUrl': 'https://tiles.example.org/{z}/{x}/{y}.png',
        'attribution': '© Example Tiles',
      });

      expect(map!.url, 'https://tiles.example.org/{z}/{x}/{y}.png');
    });

    // Every incomplete shape has to come out null rather than half-applied:
    // the caller then keeps the built-in source AND its matching credit, which
    // is the only combination that is licensing-correct.
    test('rejects an incomplete or unusable prescription', () {
      expect(parseMap('nonsense'), isNull);
      expect(parseMap(null), isNull);
      // Unknown / missing mode.
      expect(
        parseMap({'styleUrl': 'https://x.org/s.json', 'attribution': '© X'}),
        isNull,
      );
      expect(
        parseMap({
          'mode': 'satellite',
          'styleUrl': 'https://x.org/s.json',
          'attribution': '© X',
        }),
        isNull,
      );
      // URL missing, or present but for the other mode.
      expect(parseMap({'mode': 'vector', 'attribution': '© X'}), isNull);
      expect(
        parseMap({
          'mode': 'vector',
          'tileUrl': 'https://x.org/{z}/{x}/{y}.png',
          'attribution': '© X',
        }),
        isNull,
      );
      // Attribution missing or blank — the licensing footgun.
      expect(parseMap({'mode': 'vector', 'styleUrl': 'https://x.org/s'}), null);
      expect(
        parseMap({
          'mode': 'vector',
          'styleUrl': 'https://x.org/s.json',
          'attribution': '',
        }),
        isNull,
      );
      // Non-http(s) scheme.
      expect(
        parseMap({
          'mode': 'vector',
          'styleUrl': 'javascript:alert(1)',
          'attribution': '© X',
        }),
        isNull,
      );
    });
  });
}
