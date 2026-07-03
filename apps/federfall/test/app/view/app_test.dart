import 'package:federfall/app/app.dart';
import 'package:federfall/features/server_setup/setup_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('App', () {
    testWidgets('on native with no server configured, lands on setup gate', (
      tester,
    ) async {
      await tester.pumpWidget(const ProviderScope(child: App()));
      await tester.pumpAndSettle();

      expect(find.byType(SetupScreen), findsOneWidget);
    });
  });
}
