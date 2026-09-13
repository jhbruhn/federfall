import 'package:federfall/features/worklist/worklist.dart';
import 'package:federfall/features/worklist/worklist_dismissals.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The dismissal store's whole contract is that it forgets (federfall-78k6.3):
/// a row hidden today must be back tomorrow, whether or not anything wrote in
/// between.
void main() {
  final now = DateTime.now();
  final today = localDayKey(now);
  final yesterday = localDayKey(now.subtract(const Duration(days: 1)));

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<WorklistDismissals> store() async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    // Awaited so the notifier has read the prefs before anything asks it.
    await container.read(worklistDismissalsProvider.future);
    return container.read(worklistDismissalsProvider.notifier);
  }

  test('a dismissal applies today and is persisted', () async {
    final s = await store();
    await s.dismiss('k1');

    expect(s.effective(now), {'k1'});
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('worklist_dismissed_keys'), ['k1']);
    expect(prefs.getString('worklist_dismissed_day'), today);
  });

  test('restore brings the row back', () async {
    final s = await store();
    await s.dismiss('k1');
    await s.restore('k1');
    expect(s.effective(now), isEmpty);
  });

  test("yesterday's dismissals do not apply today", () async {
    SharedPreferences.setMockInitialValues({
      'worklist_dismissed_keys': ['k1'],
      'worklist_dismissed_day': yesterday,
    });
    final s = await store();
    expect(s.effective(now), isEmpty);
  });

  test('a session left open past midnight expires without a write', () async {
    final s = await store();
    await s.dismiss('k1');
    expect(s.effective(now), {'k1'});
    expect(s.effective(now.add(const Duration(days: 1))), isEmpty);
  });

  test("a dismissal on a new day starts that day's set", () async {
    SharedPreferences.setMockInitialValues({
      'worklist_dismissed_keys': ['stale'],
      'worklist_dismissed_day': yesterday,
    });
    final s = await store();
    await s.dismiss('k1');
    expect(s.effective(now), {'k1'});
  });
}
