import 'package:federfall/core/connectivity/connectivity.dart';
import 'package:federfall/core/connectivity/offline_banner.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, OnlineStatus status) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          onlineStatusProvider.overrideWith((ref) => Stream.value(status)),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: OfflineBanner()),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('shows the banner when offline', (tester) async {
    await pump(tester, OnlineStatus.offline);
    expect(find.text("You're offline — showing saved data."), findsOneWidget);
  });

  testWidgets('hides the banner when online', (tester) async {
    await pump(tester, OnlineStatus.online);
    expect(find.byType(SizedBox), findsWidgets);
    expect(find.textContaining('offline'), findsNothing);
  });
}
