import 'package:federfall/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the layout shape the nav shell uses for the rail's bottom-aligned
/// account menu: `Expanded` + `Align` inside `NavigationRail.trailing` (the
/// pattern recommended by the framework). A regression here surfaces as a
/// "ParentDataWidget" layout assertion rather than a failing expectation.
void main() {
  testWidgets('NavigationRail trailing accepts Expanded + Align', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              NavigationRail(
                selectedIndex: 0,
                destinations: const [
                  NavigationRailDestination(
                    icon: Icon(Icons.dashboard_outlined),
                    label: Text('A'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.pets_outlined),
                    label: Text('B'),
                  ),
                ],
                trailing: const Expanded(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: EdgeInsets.only(bottom: AppSpacing.md),
                      child: Icon(Icons.account_circle_outlined),
                    ),
                  ),
                ),
              ),
              const Expanded(child: SizedBox()),
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.account_circle_outlined), findsOneWidget);
  });
}
