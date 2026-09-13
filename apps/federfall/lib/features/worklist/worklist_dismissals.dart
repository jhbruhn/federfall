import 'package:federfall/features/worklist/worklist.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'worklist_dismissals.g.dart';

/// The worklist rows this device has been told to hide for the rest of the day
/// (federfall-78k6.3).
///
/// Some items genuinely cannot be finished from the list — "I saw it, not
/// today". This is that answer, and it is deliberately the weakest possible
/// version of it:
///
/// * **Per device.** It never goes to the server, so it can never make an
///   overdue dose invisible to a colleague. Two carers sharing a case see the
///   same worklist; only the phone that swiped is quieter.
/// * **Expiring.** A dismissal belongs to ONE local day, and the day is stored
///   beside the keys rather than checked at write time — so a session left open
///   past midnight goes back to showing everything without any writer having to
///   notice the date changed.
///
/// Keys are [worklistDismissalKey]s, which carry the due moment: once a dose is
/// actually given its next-due advances and the row returns, dismissed or not.
@Riverpod(keepAlive: true)
class WorklistDismissals extends _$WorklistDismissals {
  static const _keysPref = 'worklist_dismissed_keys';
  static const _dayPref = 'worklist_dismissed_day';

  /// The local day [state] belongs to, so [effective] can expire it without a
  /// write. Empty before the first load.
  String _day = '';

  @override
  Future<Set<String>> build() async {
    final prefs = await SharedPreferences.getInstance();
    _day = prefs.getString(_dayPref) ?? '';
    return (prefs.getStringList(_keysPref) ?? const <String>[]).toSet();
  }

  /// The dismissals that still apply as of [now] — nothing at all once the day
  /// they were made on has passed.
  Set<String> effective(DateTime now) {
    final keys = state.value;
    if (keys == null || _day != localDayKey(now)) return const <String>{};
    return keys;
  }

  /// Hides one row for the rest of today.
  Future<void> dismiss(String key) => _write((keys) => keys..add(key));

  /// Brings a dismissed row back — the undo behind the snackbar.
  Future<void> restore(String key) => _write((keys) => keys..remove(key));

  Future<void> _write(Set<String> Function(Set<String>) change) async {
    final today = localDayKey(DateTime.now());
    // A write on a new day starts that day's set rather than extending
    // yesterday's, which [effective] is already ignoring.
    final base = _day == today ? <String>{...?state.value} : <String>{};
    final keys = change(base);
    _day = today;
    state = AsyncData(keys);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dayPref, today);
    await prefs.setStringList(_keysPref, keys.toList());
  }
}
