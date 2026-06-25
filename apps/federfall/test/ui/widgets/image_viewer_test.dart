import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, List<String> urls, {int index = 0}) {
    return tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ImageViewerScreen(imageUrls: urls, initialIndex: index),
      ),
    );
  }

  testWidgets('shows a counter and a share action for multiple images',
      (tester) async {
    await pump(tester, const [
      'https://example.test/a.jpg',
      'https://example.test/b.jpg',
    ]);
    await tester.pump();

    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.byIcon(Icons.share_outlined), findsOneWidget);
  });

  testWidgets('swiping advances the counter', (tester) async {
    await pump(tester, const [
      'https://example.test/a.jpg',
      'https://example.test/b.jpg',
    ]);
    await tester.pump();

    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();

    expect(find.text('2 / 2'), findsOneWidget);
  });

  testWidgets('next/prev buttons page on desktop (no swipe)', (tester) async {
    await pump(tester, const [
      'https://example.test/a.jpg',
      'https://example.test/b.jpg',
    ]);
    await tester.pump();

    // On the first image: only "next" is shown.
    expect(find.byIcon(Icons.chevron_left), findsNothing);
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();

    expect(find.text('2 / 2'), findsOneWidget);
    // On the last image: only "previous" is shown.
    expect(find.byIcon(Icons.chevron_right), findsNothing);
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();

    expect(find.text('1 / 2'), findsOneWidget);
  });

  testWidgets('arrow keys page between images', (tester) async {
    await pump(tester, const [
      'https://example.test/a.jpg',
      'https://example.test/b.jpg',
    ]);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.text('1 / 2'), findsOneWidget);
  });

  testWidgets('hides the counter for a single image', (tester) async {
    await pump(tester, const ['https://example.test/only.jpg']);
    await tester.pump();

    expect(find.text('1 / 1'), findsNothing);
    expect(find.byIcon(Icons.share_outlined), findsOneWidget);
  });
}
