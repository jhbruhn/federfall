// Ignore for testing purposes
// ignore_for_file: prefer_const_constructors

import 'package:federfall/app/app.dart';
import 'package:federfall/counter/counter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('App', () {
    testWidgets('renders CounterPage', (tester) async {
      await tester.pumpWidget(App());
      expect(find.byType(CounterPage), findsOneWidget);
    });
  });
}
