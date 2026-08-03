import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/realtime/collection_events.dart';
import 'package:federfall/features/reminders/reminder_plan.dart';
import 'package:federfall/features/reminders/reminder_scheduler.dart';
import 'package:federfall/features/reminders/reminder_settings.dart';
import 'package:federfall/features/reminders/reminders.dart';
import 'package:federfall/features/worklist/worklist_providers.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart' hide Finder;
import 'package:intl/date_symbol_data_local.dart';
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

WorklistSource _source({String drug = 'Meloxicam', String vet = 'Dr. Vogel'}) =>
    WorklistSource(
      cases: const [Case(id: 'c1', animal: 'a1', status: CaseStatus.inCare)],
      medicationsDue: [
        MedicationDue(
          id: 'm1',
          caseId: 'c1',
          drug: drug,
          nextDue: _now.add(const Duration(hours: 6)),
        ),
      ],
      appointments: [
        VetAppointment(
          id: 'v1',
          caseId: 'c1',
          startsAt: _now.add(const Duration(days: 2)),
          vet: vet,
        ),
      ],
      animalNameById: const {'a1': 'Bella'},
    );

ProviderContainer _container(
  _FakeScheduler scheduler, {
  AppUser? user = _user,
  WorklistSource Function()? source,
  List<String>? subscribed,
}) {
  final container = ProviderContainer(
    overrides: [
      reminderSchedulerProvider.overrideWithValue(scheduler),
      currentUserProvider.overrideWith((ref) async => user),
      worklistSourceProvider.overrideWith(
        (ref) async => (source ?? _source)(),
      ),
      collectionEventsProvider.overrideWith((ref, collection) {
        subscribed?.add(collection);
        return const Stream<RecordSubscriptionEvent>.empty();
      }),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// The medication reminder in the most recent batch, or null.
PlannedReminder? _med(_FakeScheduler s) => s.replaced.lastOrNull
    ?.where((r) => r.channel == ReminderChannel.medication)
    .firstOrNull;

/// The appointment reminder in the most recent batch, or null.
PlannedReminder? _appt(_FakeScheduler s) => s.replaced.lastOrNull
    ?.where((r) => r.channel == ReminderChannel.appointment)
    .firstOrNull;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The appointment notification body formats a date through intl.
  setUpAll(initializeDateFormatting);

  test('both switches on: ONE replaceAll carrying both channels', () async {
    SharedPreferences.setMockInitialValues({
      'medication_reminders_enabled': true,
      'appointment_reminders_enabled': true,
    });
    final scheduler = _FakeScheduler();
    final container = _container(scheduler);

    await container.read(remindersProvider.future);

    // The regression test for federfall-fnpo's "main trap": replaceAll cancels
    // the whole pending set, so two calls would have each wipe the other.
    expect(scheduler.replaced, hasLength(1));
    expect(scheduler.initCalls, 1);
    expect(scheduler.cancelAllCalls, 0);
    expect(scheduler.replaced.single, hasLength(2));
    expect(_med(scheduler)?.id, reminderNotificationId('m1'));
    expect(
      _appt(scheduler)?.id,
      reminderNotificationId('v1', namespace: vetAppointmentReminderNamespace),
    );
  });

  test('appointments on, medications off: only appointments', () async {
    SharedPreferences.setMockInitialValues({
      'medication_reminders_enabled': false,
      'appointment_reminders_enabled': true,
    });
    final scheduler = _FakeScheduler();
    final container = _container(scheduler);

    await container.read(remindersProvider.future);

    // The gate must be "neither switch", not "the medication switch" — this is
    // the case a single-flag early return would silently kill.
    expect(scheduler.cancelAllCalls, 0);
    expect(scheduler.replaced.single, hasLength(1));
    expect(_appt(scheduler), isNotNull);
    expect(_med(scheduler), isNull);
  });

  test('medications on, appointments off: only medications', () async {
    SharedPreferences.setMockInitialValues({
      'medication_reminders_enabled': true,
      'appointment_reminders_enabled': false,
    });
    final scheduler = _FakeScheduler();
    final container = _container(scheduler);

    await container.read(remindersProvider.future);

    // The source carries an appointment regardless (the worklist needs it), so
    // this proves the planner is gated on its own switch.
    expect(scheduler.replaced.single, hasLength(1));
    expect(_med(scheduler), isNotNull);
    expect(_appt(scheduler), isNull);
  });

  test('both off: cancels everything and never schedules', () async {
    SharedPreferences.setMockInitialValues({
      'medication_reminders_enabled': false,
      'appointment_reminders_enabled': false,
    });
    final scheduler = _FakeScheduler();
    final container = _container(scheduler);

    await container.read(remindersProvider.future);

    expect(scheduler.cancelAllCalls, 1);
    expect(scheduler.replaced, isEmpty);
  });

  test('signed out: cancels everything even with both on', () async {
    SharedPreferences.setMockInitialValues({
      'medication_reminders_enabled': true,
      'appointment_reminders_enabled': true,
    });
    final scheduler = _FakeScheduler();
    final container = _container(scheduler, user: null);

    await container.read(remindersProvider.future);

    expect(scheduler.cancelAllCalls, 1);
    expect(scheduler.replaced, isEmpty);
  });

  test('only the enabled sources subscribe to realtime collections', () async {
    SharedPreferences.setMockInitialValues({
      'medication_reminders_enabled': false,
      'appointment_reminders_enabled': true,
    });
    final subscribed = <String>[];
    final container = _container(_FakeScheduler(), subscribed: subscribed);

    await container.read(remindersProvider.future);

    expect(subscribed, containsAll(['vet_appointments', 'cases']));
    expect(subscribed, isNot(contains('medications')));
    // `cases` is in both lists; the union must not subscribe to it twice.
    expect(subscribed.toSet(), hasLength(subscribed.length));
  });

  test('changing the default lead time reschedules', () async {
    SharedPreferences.setMockInitialValues({
      'medication_reminders_enabled': false,
      'appointment_reminders_enabled': true,
    });
    final scheduler = _FakeScheduler();
    final container = _container(scheduler);

    await container.read(remindersProvider.future);
    final before = _appt(scheduler)!.fireAtUtc;

    await container
        .read(appointmentReminderLeadProvider.notifier)
        .set(const Duration(hours: 3));
    await container.read(remindersProvider.future);

    expect(scheduler.replaced, hasLength(2));
    expect(
      _appt(scheduler)!.fireAtUtc,
      _now
          .add(const Duration(days: 2))
          .subtract(const Duration(hours: 3))
          .toUtc(),
    );
    expect(_appt(scheduler)!.fireAtUtc, isNot(before));
  });

  test('turning appointments off leaves medication reminders alone', () async {
    SharedPreferences.setMockInitialValues({
      'medication_reminders_enabled': true,
      'appointment_reminders_enabled': true,
    });
    final scheduler = _FakeScheduler();
    final container = _container(scheduler);

    await container.read(remindersProvider.future);
    expect(scheduler.replaced.single, hasLength(2));

    await container
        .read(appointmentRemindersEnabledProvider.notifier)
        .set(enabled: false);
    await container.read(remindersProvider.future);

    // Achieved purely through replaceAll's reconcile semantics — no selective
    // cancel path, which is what keeps stale reminders impossible.
    expect(scheduler.replaced, hasLength(2));
    expect(scheduler.replaced.last, hasLength(1));
    expect(_med(scheduler), isNotNull);
    expect(scheduler.cancelAllCalls, 0);
  });

  test('a medication source change reschedules', () async {
    SharedPreferences.setMockInitialValues({
      'medication_reminders_enabled': true,
      'appointment_reminders_enabled': false,
    });
    final scheduler = _FakeScheduler();
    var drug = 'Meloxicam';
    final container = _container(scheduler, source: () => _source(drug: drug));

    await container.read(remindersProvider.future);
    expect(scheduler.replaced, hasLength(1));

    drug = 'Baytril';
    container.invalidate(worklistSourceProvider);
    await container.read(remindersProvider.future);

    expect(scheduler.replaced, hasLength(2));
    expect(_med(scheduler)!.title, contains('Baytril'));
  });

  test('an appointment change reschedules', () async {
    SharedPreferences.setMockInitialValues({
      'medication_reminders_enabled': false,
      'appointment_reminders_enabled': true,
    });
    final scheduler = _FakeScheduler();
    var vet = 'Dr. Vogel';
    final container = _container(scheduler, source: () => _source(vet: vet));

    await container.read(remindersProvider.future);

    vet = 'Tierklinik Nord';
    container.invalidate(worklistSourceProvider);
    await container.read(remindersProvider.future);

    expect(scheduler.replaced, hasLength(2));
    expect(_appt(scheduler)!.title, contains('Tierklinik Nord'));
  });

  test(
    'a corrupt non-positive stored lead falls back to the default',
    () async {
      SharedPreferences.setMockInitialValues({
        'medication_reminders_enabled': false,
        'appointment_reminders_enabled': true,
        'appointment_reminder_lead_minutes': -1,
      });
      final scheduler = _FakeScheduler();
      final container = _container(scheduler);

      await container.read(remindersProvider.future);

      expect(
        _appt(scheduler)!.fireAtUtc,
        _now
            .add(const Duration(days: 2))
            .subtract(AppointmentReminderLead.defaultLead)
            .toUtc(),
      );
    },
  );
}
