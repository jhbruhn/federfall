import 'dart:async';

import 'package:federfall/core/connectivity/connectivity.dart';
import 'package:federfall/l10n/gen/app_localizations.dart';
import 'package:federfall/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/helpers.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  /// Status-bar inset the strip is expected to absorb while it is up.
  const statusBar = 24.0;
  const bodyKey = Key('body');

  group('OfflineNotice', () {
    late StreamController<OnlineStatus> status;

    /// Top padding the wrapped app sees — 0 once the strip owns the inset.
    late double bodyTopPadding;

    setUp(() => status = StreamController<OnlineStatus>());
    tearDown(() => status.close());

    Future<void> pump(WidgetTester tester) => tester.pumpApp(
      MediaQuery(
        // Inside `home:`, so it survives MaterialApp's own MediaQuery.
        data: const MediaQueryData(padding: EdgeInsets.only(top: statusBar)),
        child: OfflineNotice(
          child: Builder(
            builder: (context) {
              bodyTopPadding = MediaQuery.paddingOf(context).top;
              return const SizedBox.expand(key: bodyKey);
            },
          ),
        ),
      ),
      overrides: [onlineStatusProvider.overrideWith((ref) => status.stream)],
    );

    /// Where the wrapped app starts — the strip's rendered height.
    double stripHeight(WidgetTester tester) =>
        tester.getTopLeft(find.byKey(bodyKey)).dy;

    testWidgets('says nothing until a reading arrives', (tester) async {
      await pump(tester);
      await tester.pump();

      // Not knowing is not the same as being offline.
      expect(stripHeight(tester), 0);
      expect(find.bySemanticsLabel(l10n.offlineNotice), findsNothing);
      expect(bodyTopPadding, statusBar);
    });

    testWidgets('stays collapsed while online', (tester) async {
      await pump(tester);
      status.add(OnlineStatus.online);
      await tester.pumpAndSettle();

      expect(stripHeight(tester), 0);
      // The strip's text stays in the tree behind a zero-height clip, so it
      // must leave the semantics tree too, not merely go out of sight.
      expect(find.bySemanticsLabel(l10n.offlineNotice), findsNothing);
      expect(bodyTopPadding, statusBar);
    });

    testWidgets('reveals the strip and takes over the inset when offline', (
      tester,
    ) async {
      await pump(tester);
      status.add(OnlineStatus.offline);
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel(l10n.offlineNotice), findsOneWidget);
      // The band reaches the top edge of the screen: taller than the inset it
      // absorbed, and the app below no longer pads for that inset itself.
      expect(stripHeight(tester), greaterThan(statusBar));
      expect(bodyTopPadding, 0);
    });

    testWidgets('slides without a jump: content only moves down', (
      tester,
    ) async {
      await pump(tester);
      status.add(OnlineStatus.online);
      await tester.pumpAndSettle();

      final start = stripHeight(tester) + bodyTopPadding;
      status.add(OnlineStatus.offline);
      await tester.pump();

      var previous = start;
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 30));
        final offset = stripHeight(tester) + bodyTopPadding;
        expect(offset, greaterThanOrEqualTo(previous));
        previous = offset;
      }
      await tester.pumpAndSettle();
      // Whatever the frame, the content never sits above where the status bar
      // already put it.
      expect(start, statusBar);
    });

    testWidgets('retracts once the server answers again', (tester) async {
      await pump(tester);
      status.add(OnlineStatus.offline);
      await tester.pumpAndSettle();
      status.add(OnlineStatus.online);
      await tester.pumpAndSettle();

      expect(stripHeight(tester), 0);
      expect(find.bySemanticsLabel(l10n.offlineNotice), findsNothing);
      expect(bodyTopPadding, statusBar);
    });

    testWidgets('wraps its line instead of truncating it when text scales', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpApp(
        const MediaQuery(
          data: MediaQueryData(
            padding: EdgeInsets.only(top: statusBar),
            textScaler: TextScaler.linear(2),
          ),
          child: OfflineNotice(child: SizedBox.expand(key: bodyKey)),
        ),
        overrides: [onlineStatusProvider.overrideWith((ref) => status.stream)],
      );
      status.add(OnlineStatus.offline);
      await tester.pumpAndSettle();

      // Taller than one scaled line: the sentence wrapped rather than clipped.
      final scaled = stripHeight(tester);
      expect(scaled, greaterThan(statusBar + 40));
      // ...but bounded, so the notice never takes more of the screen than the
      // work it interrupts.
      expect(tester.widget<Text>(find.text(l10n.offlineNotice)).maxLines, 3);
      expect(scaled, lessThan(tester.view.physicalSize.height / 3));
    });
  });
}
