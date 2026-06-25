import 'package:federfall/core/connectivity/connectivity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('confirmStatus', () {
    // A zero gap keeps the retry logic synchronous-fast for tests; production
    // uses the real 1s spacing.
    const noGap = Duration.zero;

    test('returns online on the first successful probe without retrying',
        () async {
      var calls = 0;
      final status = await confirmStatus(
        () async {
          calls++;
          return OnlineStatus.online;
        },
        gap: noGap,
      );

      expect(status, OnlineStatus.online);
      expect(calls, 1);
    });

    test('treats a single failed probe as tentative and recovers', () async {
      var calls = 0;
      // First probe fails (transient blip), second succeeds.
      final status = await confirmStatus(
        () async {
          calls++;
          return calls == 1 ? OnlineStatus.offline : OnlineStatus.online;
        },
        gap: noGap,
      );

      expect(status, OnlineStatus.online);
      expect(calls, 2);
    });

    test('commits to offline after consecutive failures', () async {
      var calls = 0;
      final status = await confirmStatus(
        () async {
          calls++;
          return OnlineStatus.offline;
        },
        gap: noGap,
      );

      expect(status, OnlineStatus.offline);
      expect(calls, 2); // default _offlineConfirmAttempts
    });

    test('bails out early when no longer mounted during the gap', () async {
      var calls = 0;
      final status = await confirmStatus(
        () async {
          calls++;
          return OnlineStatus.offline;
        },
        gap: noGap,
        isMounted: () => false, // provider disposed before the retry
      );

      expect(status, OnlineStatus.offline);
      expect(calls, 1);
    });
  });
}
