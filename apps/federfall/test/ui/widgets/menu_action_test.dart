import 'package:federfall/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/helpers.dart';

void main() {
  MenuAction action(String label, {bool destructive = false}) => MenuAction(
    icon: destructive ? Icons.delete_outline : Icons.edit_outlined,
    label: label,
    onTap: () {},
    destructive: destructive,
  );

  /// Opens a menu built from [actions] and returns once it is on screen.
  Future<void> openMenu(WidgetTester tester, List<MenuAction> actions) async {
    await tester.pumpApp(
      Scaffold(
        appBar: AppBar(
          actions: [
            PopupMenuButton<void>(
              icon: const Icon(Icons.more_vert),
              itemBuilder: (_) => buildMenuItems(actions),
            ),
          ],
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
  }

  Color? labelColor(WidgetTester tester, String label) =>
      tester.widget<Text>(find.text(label)).style?.color;

  group('buildMenuItems', () {
    testWidgets('separates a destructive entry from the safe ones above it', (
      tester,
    ) async {
      await openMenu(tester, [
        action('Edit'),
        action('Delete', destructive: true),
      ]);

      expect(find.byType(PopupMenuDivider), findsOneWidget);
    });

    testWidgets('gives a lone destructive entry no divider', (tester) async {
      await openMenu(tester, [action('Delete', destructive: true)]);

      // Nothing to separate it from; a rule above a single row reads as a
      // missing item.
      expect(find.byType(PopupMenuDivider), findsNothing);
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('draws one divider for a run of destructive entries', (
      tester,
    ) async {
      await openMenu(tester, [
        action('Edit'),
        action('Remove', destructive: true),
        action('Delete', destructive: true),
      ]);

      expect(find.byType(PopupMenuDivider), findsOneWidget);
    });

    testWidgets('tints only the destructive entry, and gives every entry an '
        'icon so the colour is never the sole signal', (tester) async {
      await openMenu(tester, [
        action('Edit'),
        action('Delete', destructive: true),
      ]);

      final errorColor = Theme.of(
        tester.element(find.text('Delete')),
      ).colorScheme.error;
      expect(labelColor(tester, 'Delete'), errorColor);
      expect(labelColor(tester, 'Edit'), isNull);
      expect(
        tester.widget<Icon>(find.byIcon(Icons.delete_outline)).color,
        errorColor,
      );
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    });
  });
}
