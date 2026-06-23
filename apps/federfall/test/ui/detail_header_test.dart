import 'package:federfall/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(home: Scaffold(body: child)),
);

void main() {
  testWidgets('renders title, subtitle and chip', (tester) async {
    await _pump(
      tester,
      const DetailHeader(
        title: 'Pip',
        subtitle: 'Columba livia · 2026-014',
        chipLabel: 'In care',
      ),
    );

    expect(find.text('Pip'), findsOneWidget);
    expect(find.text('Columba livia · 2026-014'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'In care'), findsOneWidget);
  });

  testWidgets('omits subtitle and chip when not provided', (tester) async {
    await _pump(tester, const DetailHeader(title: 'Pip'));

    expect(find.text('Pip'), findsOneWidget);
    expect(find.byType(Chip), findsNothing);
  });

  testWidgets('shows the leading slot when given', (tester) async {
    await _pump(
      tester,
      const DetailHeader(
        title: 'Pip',
        leading: Icon(Icons.pets, key: Key('avatar')),
      ),
    );

    expect(find.byKey(const Key('avatar')), findsOneWidget);
  });
}
