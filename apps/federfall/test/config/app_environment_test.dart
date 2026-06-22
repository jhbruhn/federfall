import 'package:federfall/config/app_environment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppEnvironment', () {
    // These assertions reflect the compile-time defaults that apply when no
    // --dart-define-from-file is supplied (as in a bare `flutter test`).
    test('defaults to the development flavor', () {
      expect(AppEnvironment.flavorName, 'development');
      expect(AppEnvironment.flavor, AppFlavor.development);
    });

    test('defaults the app name to Federfall', () {
      expect(AppEnvironment.appName, 'Federfall');
    });

    test('has no PocketBase URL override by default', () {
      expect(AppEnvironment.pocketbaseUrlOverride, isEmpty);
      expect(AppEnvironment.hasPocketbaseUrlOverride, isFalse);
    });

    test('is not production by default', () {
      expect(AppEnvironment.isProduction, isFalse);
    });
  });
}
