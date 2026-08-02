import 'package:federfall/core/server/server_compatibility.dart';
import 'package:federfall/core/server/server_info.dart';
import 'package:flutter_test/flutter_test.dart';

ServerInfo _info({required String version, String? minClient}) => ServerInfo(
  version: version,
  name: 'Test',
  auth: const ServerAuthOptions(),
  minClient: minClient,
);

void main() {
  group('checkServerCompatibility', () {
    test('accepts equal majors regardless of minor and patch', () {
      expect(
        checkServerCompatibility(
          appVersion: '2.0.0',
          info: _info(version: '2.14'),
        ),
        ServerCompatibility.compatible,
      );
      expect(
        checkServerCompatibility(
          appVersion: '2.14.3',
          info: _info(version: '2.0'),
        ),
        ServerCompatibility.compatible,
      );
    });

    test('an older app is told to update itself', () {
      expect(
        checkServerCompatibility(
          appVersion: '1.9.9',
          info: _info(version: '2.0'),
        ),
        ServerCompatibility.clientTooOld,
      );
    });

    test('a newer app blames the server, not the user', () {
      // The likely case for a self-hosted instance: the APK auto-updated
      // while the container did not.
      expect(
        checkServerCompatibility(
          appVersion: '3.0.0',
          info: _info(version: '2.9'),
        ),
        ServerCompatibility.serverTooOld,
      );
    });

    test('honours a minClient floor inside a matching major', () {
      expect(
        checkServerCompatibility(
          appVersion: '2.3.0',
          info: _info(version: '2.9', minClient: '2.4.0'),
        ),
        ServerCompatibility.clientTooOld,
      );
      expect(
        checkServerCompatibility(
          appVersion: '2.4.0',
          info: _info(version: '2.9', minClient: '2.4.0'),
        ),
        ServerCompatibility.compatible,
      );
    });

    group('fails open', () {
      test('when discovery returned nothing', () {
        expect(
          checkServerCompatibility(appVersion: '1.0.0', info: null),
          ServerCompatibility.compatible,
        );
      });

      test('for an unversioned dev backend', () {
        // A locally built image has no FEDERFALL_VERSION build-arg and reports
        // "0.0" — that must not lock a released app out of a dev stack.
        expect(
          checkServerCompatibility(
            appVersion: '2.1.0',
            info: _info(version: '0.0'),
          ),
          ServerCompatibility.compatible,
        );
      });

      test('when PackageInfo could not resolve an app version', () {
        expect(
          checkServerCompatibility(
            appVersion: '0.0.0',
            info: _info(version: '2.1'),
          ),
          ServerCompatibility.compatible,
        );
      });

      test('on a version string that does not parse', () {
        expect(
          checkServerCompatibility(
            appVersion: 'nightly',
            info: _info(version: '2.1'),
          ),
          ServerCompatibility.compatible,
        );
      });

      test('on a dev minClient floor', () {
        expect(
          checkServerCompatibility(
            appVersion: '0.10.0',
            info: _info(version: '0.11', minClient: '0.0.0'),
          ),
          ServerCompatibility.compatible,
        );
      });
    });
  });
}
