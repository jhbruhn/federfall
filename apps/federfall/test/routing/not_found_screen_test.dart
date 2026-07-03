import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/routing/not_found_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, {Uri? uri}) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: NotFoundScreen(uri: uri),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the not-found message and the unmatched uri', (
    tester,
  ) async {
    await pump(tester, uri: Uri.parse('/nope'));

    expect(find.text('Page not found'), findsOneWidget);
    expect(find.text('/nope'), findsOneWidget);
    expect(find.text('Go to home'), findsOneWidget);
  });

  testWidgets('shows an empty subtitle when no uri is given', (tester) async {
    await pump(tester);

    expect(find.text('Page not found'), findsOneWidget);
    expect(find.text(''), findsOneWidget);
  });
}
