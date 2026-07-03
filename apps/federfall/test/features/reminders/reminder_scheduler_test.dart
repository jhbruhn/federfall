import 'package:federfall/features/reminders/reminder_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NoopReminderScheduler', () {
    final scheduler = NoopReminderScheduler();

    test('init completes without doing anything', () async {
      await scheduler.init(onSelect: (_) {});
    });

    test('requestPermissions always denies', () async {
      expect(await scheduler.requestPermissions(), isFalse);
    });

    test('replaceAll and cancelAll are no-ops', () async {
      await scheduler.replaceAll(const []);
      await scheduler.cancelAll();
    });
  });
}
