import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/realtime/collection_events.dart';
import 'package:federfall/features/reminders/reminder_plan.dart';
import 'package:federfall/features/reminders/reminder_scheduler.dart';
import 'package:federfall/features/reminders/reminder_settings.dart';
import 'package:federfall/features/worklist/worklist_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/routing/router.dart';
import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'medication_reminders.g.dart';

/// The base collections whose changes can move a prescription's `next_due`
/// (the `medication_due` view derives from them): a dose logged, a
/// prescription created/edited/ended, a case handed off or disposed.
const _reminderLiveCollections = [
  'medications',
  'medication_administrations',
  'cases',
];

/// Keeps the device's scheduled medication reminders in sync with the server
/// (federfall-3uz): whenever the worklist source data changes, the full set of
/// OS-scheduled notifications is recomputed and replaced.
///
/// Reconcile triggers, all funnelled through [worklistSourceProvider]:
///   * app start — the root `App` widget activates this provider, which
///     builds once the signed-in user resolves;
///   * a dose logged / prescription changed / case handed off — realtime
///     events on the base collections (own writes echo back too), plus the
///     explicit invalidations the sheets already do;
///   * worklist refreshes (pull-to-refresh, reconnect catch-up).
///
/// Sign-out and toggling reminders off cancel everything scheduled.
///
/// KNOWN LIMITATION (accepted for v1): there is no server push and no
/// background fetch, so a prescription added or changed by another user (or on
/// another device) only (re)schedules here once this app next runs and
/// reconciles — the realtime listeners cover changes while it is open. The
/// toggle's subtitle says as much to the user.
@Riverpod(keepAlive: true)
class MedicationReminders extends _$MedicationReminders {
  @override
  Future<void> build() async {
    final scheduler = ref.watch(reminderSchedulerProvider);

    // Everything below the gates stays untouched while reminders are off (or
    // nobody is signed in): no realtime subscriptions, no plugin init — an
    // unconfigured/offline start must not pull on the PocketBase client.
    final enabled =
        await ref.watch(medicationRemindersEnabledProvider.future);
    final user =
        enabled ? await ref.watch(currentUserProvider.future) : null;
    if (!enabled || user == null) {
      await scheduler.cancelAll();
      return;
    }

    // While the app runs, base-collection changes (from this device or
    // others) re-fetch the source and land back here via the watch below.
    for (final collection in _reminderLiveCollections) {
      ref.listen(collectionEventsProvider(collection), (_, next) {
        if (next.value != null) ref.invalidate(worklistSourceProvider);
      });
    }

    await scheduler.init(
      onSelect: (payload) => ref.read(routerProvider).go(payload),
    );

    final source = await ref.watch(worklistSourceProvider.future);
    await scheduler.replaceAll(
      planMedicationReminders(
        // The app's UI language is fixed (app.dart pins the locale), so the
        // notification copy follows it rather than the device language.
        l10n: lookupAppLocalizations(const Locale('de')),
        medicationsDue: source.medicationsDue,
        casesById: {for (final c in source.cases) c.id: c},
        animalNameById: source.animalNameById,
        now: DateTime.now(),
      ),
    );
  }
}
