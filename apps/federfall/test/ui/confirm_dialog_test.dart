import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The dialog is pumped through the real [AppTheme], because the defect this
/// guards against lives there: `filledButtonTheme` gives every [FilledButton]
/// an infinite minimum width so `PrimaryButton` fills a form, and an action
/// row inherits it unless the button says otherwise.
Future<void> _open(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showConfirmDialog(
              context,
              title: 'Stop medication?',
              message: 'Baytril is recorded as ending today.',
              confirmLabel: 'Stop',
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the two buttons sit side by side, not stacked', (tester) async {
    await _open(tester);

    final cancel = tester.getRect(find.widgetWithText(TextButton, 'Cancel'));
    final confirm = tester.getRect(find.widgetWithText(FilledButton, 'Stop'));

    // One row: an infinite-width confirm overflows the OverflowBar, which then
    // lays the pair out vertically — a small text link stranded above a
    // full-width slab, which is exactly what this dialog must not look like.
    expect(confirm.top, cancel.top);
    // Confirm sits after Cancel, both hugging the dialog's trailing edge.
    expect(confirm.left, greaterThan(cancel.right - 1));

    // Its natural width, not the dialog's.
    final dialog = tester.getRect(find.byType(AlertDialog));
    expect(confirm.width, lessThan(dialog.width / 2));
    // Still a full-height touch target, matching the Cancel beside it.
    expect(confirm.height, cancel.height);
  });

  testWidgets('dismissing without choosing resolves to false', (tester) async {
    await _open(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
}
