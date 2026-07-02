import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => ProviderScope(
      child: MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    );

void main() {
  testWidgets('LoadingView shows spinner and default label', (tester) async {
    await tester.pumpWidget(_host(const LoadingView()));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Wird geladen…'), findsOneWidget);
  });

  testWidgets('ErrorView shows retry that fires callback', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      _host(ErrorView(message: 'Boom', onRetry: () => tapped = true)),
    );
    expect(find.text('Boom'), findsOneWidget);
    await tester.tap(find.text('Erneut versuchen'));
    expect(tapped, isTrue);
  });

  testWidgets('AsyncValueView renders each state', (tester) async {
    await tester.pumpWidget(
      _host(
        AsyncValueView<int>(
          value: const AsyncData(42),
          data: (v) => Text('value $v'),
        ),
      ),
    );
    expect(find.text('value 42'), findsOneWidget);

    await tester.pumpWidget(
      _host(
        AsyncValueView<int>(
          value: const AsyncLoading(),
          data: (v) => Text('value $v'),
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpWidget(
      _host(
        AsyncValueView<int>(
          value: AsyncError(Exception('x'), StackTrace.empty),
          data: (v) => Text('value $v'),
          errorMessage: (_) => 'failed',
        ),
      ),
    );
    expect(find.text('failed'), findsOneWidget);
  });

  testWidgets('AsyncValueView maps errors to localized copy by default',
      (tester) async {
    await tester.pumpWidget(
      _host(
        AsyncValueView<int>(
          value: const AsyncError(
            RepositoryException(
              'boom',
              kind: RepositoryErrorKind.network,
            ),
            StackTrace.empty,
          ),
          data: (v) => Text('value $v'),
        ),
      ),
    );
    expect(find.textContaining('Du bist offline'), findsOneWidget);

    await tester.pumpWidget(
      _host(
        AsyncValueView<int>(
          value: AsyncError(Exception('x'), StackTrace.empty),
          data: (v) => Text('value $v'),
        ),
      ),
    );
    expect(find.text('Etwas ist schiefgelaufen'), findsOneWidget);
  });

  testWidgets('PrimaryButton swaps to spinner and disables while loading',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        PrimaryButton(
          label: 'Speichern',
          isLoading: true,
          onPressed: () => taps++,
        ),
      ),
    );
    expect(find.text('Speichern'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byType(PrimaryButton));
    expect(taps, 0);
  });
}
