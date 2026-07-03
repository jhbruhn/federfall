import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/realtime/collection_events.dart';
import 'package:federfall/features/reminders/medication_reminders.dart';
import 'package:federfall/features/reminders/reminder_plan.dart';
import 'package:federfall/features/reminders/reminder_scheduler.dart';
import 'package:federfall/features/worklist/worklist_providers.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart' hide Finder;
import 'package:pocketbase/pocketbase.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records every call so the reconcile behaviour can be asserted without any
/// platform plugin.
class _FakeScheduler implements ReminderScheduler {
  int initCalls = 0;
  int cancelAllCalls = 0;
  final List<List<PlannedReminder>> replaced = [];

  @override
  Future<void> init({required void Function(String payload) onSelect}) async {
    initCalls++;
  }

  @override
  Future<bool> requestPermissions() async => true;

  @override
  Future<void> replaceAll(List<PlannedReminder> reminders) async {
    replaced.add(reminders);
  }

  @override
  Future<void> cancelAll() async {
    cancelAllCalls++;
  }
}

const _user = AppUser(id: 'u1', email: 'carer@example.com');

final _now = DateTime.now();

WorklistSource _source({String drug = 'Meloxicam'}) => WorklistSource(
  cases: const [Case(id: 'c1', animal: 'a1', status: CaseStatus.inCare)],
  medicationsDue: [
    MedicationDue(
      id: 'm1',
      caseId: 'c1',
      drug: drug,
      nextDue: _now.add(const Duration(hours: 6)),
    ),
  ],
  animalNameById: const {'a1': 'Bella'},
);

ProviderContainer _container(
  _FakeScheduler scheduler, {
  AppUser? user = _user,
  WorklistSource Function()? source,
}) {
  final container = ProviderContainer(
    overrides: [
      reminderSchedulerProvider.overrideWithValue(scheduler),
      currentUserProvider.overrideWith((ref) async => user),
      worklistSourceProvider.overrideWith(
        (ref) async => (source ?? _source)(),
      ),
      collectionEventsProvider.overrideWith(
        (ref, collection) => const Stream<RecordSubscriptionEvent>.empty(),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'enabled + signed in: schedules the due set (and inits the plugin)',
    () async {
      SharedPreferences.setMockInitialValues({
        'medication_reminders_enabled': true,
      });
      final scheduler = _FakeScheduler();
      final container = _container(scheduler);

      await container.read(medicationRemindersProvider.future);

      expect(scheduler.initCalls, 1);
      expect(scheduler.replaced, hasLength(1));
      expect(scheduler.replaced.single.single.id, reminderNotificationId('m1'));
      expect(scheduler.cancelAllCalls, 0);
    },
  );

  test('reminders disabled: cancels everything and never schedules', () async {
    SharedPreferences.setMockInitialValues({
      'medication_reminders_enabled': false,
    });
    final scheduler = _FakeScheduler();
    final container = _container(scheduler);

    await container.read(medicationRemindersProvider.future);

    expect(scheduler.cancelAllCalls, 1);
    expect(scheduler.replaced, isEmpty);
  });

  test('signed out: cancels everything even with reminders enabled', () async {
    SharedPreferences.setMockInitialValues({
      'medication_reminders_enabled': true,
    });
    final scheduler = _FakeScheduler();
    final container = _container(scheduler, user: null);

    await container.read(medicationRemindersProvider.future);

    expect(scheduler.cancelAllCalls, 1);
    expect(scheduler.replaced, isEmpty);
  });

  test(
    'a source change (dose logged, prescription edited) reschedules',
    () async {
      SharedPreferences.setMockInitialValues({
        'medication_reminders_enabled': true,
      });
      final scheduler = _FakeScheduler();
      var drug = 'Meloxicam';
      final container = _container(
        scheduler,
        source: () => _source(drug: drug),
      );

      await container.read(medicationRemindersProvider.future);
      expect(scheduler.replaced, hasLength(1));

      drug = 'Baytril';
      container.invalidate(worklistSourceProvider);
      await container.read(medicationRemindersProvider.future);

      expect(scheduler.replaced, hasLength(2));
      expect(scheduler.replaced.last.single.title, contains('Baytril'));
    },
  );
}
