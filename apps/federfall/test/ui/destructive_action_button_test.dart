import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// federfall-qo8f: the destructive confirm must never be distinguishable from
/// Cancel by colour alone (WCAG 2.1 SC 1.4.1). These assert the *shape*, which
/// is the part a colour-blind or squinting user can still read.
Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Center(child: child)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the destructive action is FILLED in the error colours, so it '
      'differs from a text-button Cancel in shape and weight', (tester) async {
    var tapped = false;
    await _pump(
      tester,
      DestructiveActionButton(
        label: 'Delete animal',
        onPressed: () => tapped = true,
      ),
    );

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Delete animal'),
    );
    final scheme = AppTheme.light.colorScheme;
    expect(
      button.style?.backgroundColor?.resolve({}),
      scheme.error,
      reason: 'the error colour is redundant on top of the fill, not instead',
    );
    expect(button.style?.foregroundColor?.resolve({}), scheme.onError);
    expect(find.byType(OutlinedButton), findsNothing);

    await tester.tap(find.byType(FilledButton));
    expect(tapped, isTrue);
  });

  testWidgets('an icon adds a third redundant signal for the cascade deletes', (
    tester,
  ) async {
    await _pump(
      tester,
      DestructiveActionButton(
        label: 'Delete animal',
        icon: Icons.delete_forever,
        onPressed: () {},
      ),
    );

    expect(find.byIcon(Icons.delete_forever), findsOne);
    expect(find.widgetWithText(FilledButton, 'Delete animal'), findsOne);
  });

  testWidgets('a DEMOTED destructive action is outlined, so a reversible '
      'alternative can hold the filled primary slot', (tester) async {
    await _pump(
      tester,
      DestructiveActionButton(
        label: 'Delete anyway',
        demoted: true,
        onPressed: () {},
      ),
    );

    // Still unmistakably not Cancel (it has a border), but it no longer
    // outranks the safe route.
    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Delete anyway'),
    );
    final scheme = AppTheme.light.colorScheme;
    expect(button.style?.foregroundColor?.resolve({}), scheme.error);
    expect(button.style?.side?.resolve({})?.color, scheme.error);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('the code-list dialog stacks all three roles as three distinct '
      'shapes: text Cancel, outlined delete, filled alternative', (
    tester,
  ) async {
    await _pump(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showDialog<DestructiveChoice>(
            context: context,
            builder: (_) => const DestructiveDialog(
              title: 'Delete condition',
              intro: '"Trichomoniasis" is still in use.',
              bullets: [('3 recorded diagnoses use this condition', true)],
              confirmLabel: 'Delete anyway',
              alternativeLabel: 'Deactivate instead',
              closingNote: 'This cannot be undone.',
            ),
          ),
          child: const Text('open'),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextButton, 'Cancel'), findsOne);
    expect(find.widgetWithText(OutlinedButton, 'Delete anyway'), findsOne);
    expect(find.widgetWithText(FilledButton, 'Deactivate instead'), findsOne);
  });

  testWidgets('a two-action dialog gives the destructive action the filled '
      'slot, since nothing safer competes for it', (tester) async {
    await _pump(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showDialog<DestructiveChoice>(
            context: context,
            builder: (_) => const DestructiveDialog(
              title: 'Delete animal',
              intro: 'Delete "Lotte"?',
              bullets: [('2 cases', false)],
              confirmLabel: 'Delete animal',
              confirmIcon: Icons.delete_forever,
              closingNote: 'This cannot be undone.',
            ),
          ),
          child: const Text('open'),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextButton, 'Cancel'), findsOne);
    expect(find.widgetWithText(FilledButton, 'Delete animal'), findsOne);
    expect(find.byIcon(Icons.delete_forever), findsOne);
    expect(find.byType(OutlinedButton), findsNothing);
  });
}
