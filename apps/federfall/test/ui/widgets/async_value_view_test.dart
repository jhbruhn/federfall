import 'package:federfall/l10n/gen/app_localizations.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  RepositoryException repo(int status) =>
      RepositoryException.fromClient(ClientException(statusCode: status));

  /// Loads once, then fails the next refresh with [error] — the real shape of a
  /// connection dropping under a screen that already has its data, which is the
  /// only way to get an `AsyncError` that still carries its previous value.
  Future<void> pumpThenFail(WidgetTester tester, Exception error) async {
    var shouldFail = false;
    final source = FutureProvider<String>(
      (ref) async {
        if (shouldFail) throw error;
        return 'loaded';
      },
      // No automatic retry: the test asserts what the *failed* state renders.
      retry: (retryCount, error) => null,
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => AsyncValueView<String>(
                value: ref.watch(source),
                data: Text.new,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('loaded'), findsOneWidget);

    shouldFail = true;
    container.invalidate(source);
    await tester.pumpAndSettle();
  }

  group('AsyncValueView', () {
    testWidgets('keeps data on screen when a refresh loses the connection', (
      tester,
    ) async {
      await pumpThenFail(tester, repo(0));

      // `OfflineNotice` states the cause app-wide; blanking a populated list
      // would only cost the user their place (federfall-gmnc).
      expect(find.text('loaded'), findsOneWidget);
      expect(find.byType(ErrorView), findsNothing);
    });

    testWidgets('still surfaces a non-network failure over stale data', (
      tester,
    ) async {
      await pumpThenFail(tester, repo(403));

      expect(find.text('loaded'), findsNothing);
      expect(find.text(l10n.errorUnauthorized), findsOneWidget);
    });

    testWidgets('reports the missing content when nothing loaded at all', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: AsyncValueView<String>(
                value: AsyncError(repo(0), StackTrace.empty),
                data: Text.new,
              ),
            ),
          ),
        ),
      );

      expect(find.text(l10n.errorLoadFailed), findsOneWidget);
      // Not the write-flavoured copy, which promises a kept entry.
      expect(find.text(l10n.errorOffline), findsNothing);
    });
  });
}
