import 'package:federfall/app/app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('App', () {
    testWidgets('renders HomePlaceholder', (tester) async {
      await tester.pumpWidget(const ProviderScope(child: App()));
      expect(find.byType(HomePlaceholder), findsOneWidget);
    });
  });
}
