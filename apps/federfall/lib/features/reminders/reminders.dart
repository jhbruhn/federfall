import 'package:federfall/core/async/parallel_wait.dart';
import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/features/reminders/reminder_plan.dart';
import 'package:federfall/features/reminders/reminder_scheduler.dart';
import 'package:federfall/features/reminders/reminder_settings.dart';
import 'package:federfall/features/worklist/worklist_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/routing/router.dart';
import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:zugvogel_pb_client/zugvogel_pb_client.dart'
    show collectionEventsProvider;

part 'reminders.g.dart';

/// The base collections whose changes can move a prescription's `next_due`
/// (the `medication_due` view derives from them): a dose logged, a
/// prescription created/edited/ended, a case handed off or disposed.
const _medicationLiveCollections = [
  'medications',
  'medication_administrations',
  'cases',
];

/// The base collections whose changes can move an appointment's fire time: the
/// appointment itself, or a case leaving this carer's scope. `cases` overlaps
/// the medication list, which is why the two are unioned through a Set below
/// rather than concatenated.
const _appointmentLiveCollections = ['vet_appointments', 'cases'];

/// Keeps the device's scheduled reminders in sync with the server
/// (federfall-3uz for medication doses, federfall-fnpo for vet appointments):
/// whenever the worklist source data changes, the full set of OS-scheduled
/// notifications is recomputed and replaced.
///
/// Reconcile triggers, all funnelled through [worklistSourceProvider]:
///   * app start — the root `App` widget activates this provider, which
///     builds once the signed-in user resolves;
///   * a dose logged / prescription changed / appointment edited / case handed
///     off — realtime events on the base collections (own writes echo back
///     too), plus the explicit invalidations the sheets already do;
///   * either reminder switch or the default lead time changing;
///   * worklist refreshes (pull-to-refresh, reconnect catch-up).
///
/// Sign-out, and having both switches off, cancel everything scheduled.
///
/// Both sources go through ONE [ReminderScheduler.replaceAll] because that call
/// cancels the whole pending set first — planning them in two calls would have
/// each wipe the other's notifications.
///
/// KNOWN LIMITATION (accepted for v1): there is no server push and no
/// background fetch, so a prescription or appointment added or changed by
/// another user (or on another device) only (re)schedules here once this app
/// next runs and reconciles — the realtime listeners cover changes while it is
/// open. The toggles' subtitles say as much to the user.
@Riverpod(keepAlive: true)
class Reminders extends _$Reminders {
  @override
  Future<void> build() async {
    final scheduler = ref.watch(reminderSchedulerProvider);

    // Both switches are watched unconditionally, so flipping either one
    // reconciles. Everything below the gate stays untouched while both are off
    // (or nobody is signed in): no realtime subscriptions, no plugin init — an
    // unconfigured/offline start must not pull on the PocketBase client.
    final (medsOn, appointmentsOn) = await (
      ref.watch(medicationRemindersEnabledProvider.future),
      ref.watch(appointmentRemindersEnabledProvider.future),
    ).waitUnwrapped;
    final anyOn = medsOn || appointmentsOn;
    // Only "is anyone signed in" is used, so only that is watched: watching
    // the user re-planned every reminder on each token refresh, i.e. on every
    // window refocus (federfall-bpw6).
    final signedIn =
        anyOn &&
        await ref.watch(currentUserProvider.selectAsync((u) => u != null));
    if (!signedIn) {
      await scheduler.cancelAll();
      return;
    }

    // Watched (not read), so editing the default reschedules immediately. Null
    // doubles as "appointments are off", which is what gates the planner below.
    final defaultLead = appointmentsOn
        ? await ref.watch(appointmentReminderLeadProvider.future)
        : null;

    // While the app runs, base-collection changes (from this device or others)
    // re-fetch the source and land back here via the watch below. Only the
    // collections an *enabled* source depends on get a subscription.
    for (final collection in <String>{
      if (medsOn) ..._medicationLiveCollections,
      if (appointmentsOn) ..._appointmentLiveCollections,
    }) {
      ref.listen(collectionEventsProvider(collection), (_, next) {
        if (next.value != null) ref.invalidate(worklistSourceProvider);
      });
    }

    await scheduler.init(
      onSelect: (payload) => ref.read(routerProvider).go(payload),
    );

    // Same locale the UI resolves to (federfall-qdsa) — there is no
    // BuildContext out here, so read the device preference directly. A
    // language change mid-run only reaches already-scheduled notifications
    // on the next reconcile, which is close enough: the OS restarts the app
    // on a system locale change anyway.
    final l10n = lookupAppLocalizations(
      resolveAppLocale(WidgetsBinding.instance.platformDispatcher.locales),
    );
    final source = await ref.watch(worklistSourceProvider.future);
    final casesById = {for (final c in source.cases) c.id: c};
    final now = DateTime.now();

    // Each planner is gated on its OWN switch, not just on the shared gate
    // above: the worklist needs both source lists whatever the switches say, so
    // planning one of them while its switch is off would schedule reminders for
    // a disabled feature.
    await scheduler.replaceAll(
      mergeReminders(
        appointments: defaultLead == null
            ? const []
            : planVetAppointmentReminders(
                l10n: l10n,
                appointments: source.appointments,
                casesById: casesById,
                animalNameById: source.animalNameById,
                defaultLead: defaultLead,
                now: now,
              ),
        medications: medsOn
            ? planMedicationReminders(
                l10n: l10n,
                medicationsDue: source.medicationsDue,
                casesById: casesById,
                animalNameById: source.animalNameById,
                now: now,
              )
            : const [],
      ),
    );
  }
}
