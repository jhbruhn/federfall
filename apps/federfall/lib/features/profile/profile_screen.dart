import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/auth/roles.dart';
import 'package:federfall/core/auth/sign_out.dart';
import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/core/pocketbase/user_agent_client.dart';
import 'package:federfall/core/server/server_info_provider.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/printing/printer_config_sheet.dart';
import 'package:federfall/features/printing/printer_labels.dart';
import 'package:federfall/features/printing/printer_service.dart';
import 'package:federfall/features/printing/printer_settings.dart';
import 'package:federfall/features/profile/edit_profile_sheet.dart';
import 'package:federfall/features/reminders/reminder_lead.dart';
import 'package:federfall/features/reminders/reminder_scheduler.dart';
import 'package:federfall/features/reminders/reminder_settings.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/routing/back_or_home.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Minimal profile screen (FED-3.3): shows the signed-in user's details and
/// hosts the sign-out action.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final user = ref.watch(currentUserProvider);

    // Profile is a top-level route over the shell, so it can end up with
    // an empty back stack — restored on cold start, or after a redirect refresh
    // (this screen mutates currentUserProvider via the MFA toggle / edit sheet,
    // which bumps the router's refresh listenable). [BackOrHomeButton] and
    // [BackOrHomeScope] fall back to the home landing in that case, for the app
    // bar and the system back gesture respectively.
    return BackOrHomeScope(
      child: Scaffold(
        appBar: AppBar(
          leading: const BackOrHomeButton(),
          title: Text(l10n.profileTitle),
          actions: [
            if (user.value case final u?)
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: l10n.profileEditTitle,
                onPressed: () => showEditProfileSheet(context, u),
              ),
          ],
        ),
        body: AsyncValueView<AppUser?>(
          value: user,
          onRetry: () => ref.invalidate(currentUserProvider),
          data: (u) => u == null
              ? EmptyView(message: l10n.errorUnauthorized)
              : _ProfileBody(u),
        ),
      ),
    );
  }
}

class _ProfileBody extends StatelessWidget {
  const _ProfileBody(this.user);

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final role = user.role;

    return ContentBounds(
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.sm),
        children: [
          if (user.name != null && user.name!.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: Text(l10n.profileNameLabel),
              subtitle: Text(user.name!),
            ),
          ListTile(
            leading: const Icon(Icons.alternate_email),
            title: Text(l10n.profileEmailLabel),
            subtitle: Text(user.email),
          ),
          ListTile(
            leading: const Icon(Icons.security_outlined),
            title: Text(l10n.profileRoleLabel),
            subtitle: Text(role == null ? '—' : userRoleLabel(l10n, role)),
          ),
          if (user.phone != null && user.phone!.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.phone_outlined),
              title: Text(l10n.profilePhoneLabel),
              subtitle: Text(user.phone!),
            ),
          const Divider(height: AppSpacing.lg),
          _MfaToggle(enabled: user.mfaEnabled),
          // Local notifications don't exist on the web build.
          if (!kIsWeb) ...[
            const _RemindersToggle(),
            const _AppointmentRemindersToggle(),
            const _AppointmentLeadRow(),
          ],
          // unified_esc_pos_printer has no web support (federfall-i0wq).
          if (!kIsWeb) ...[
            const Divider(height: AppSpacing.lg),
            const _PrinterSection(),
          ],
          const Divider(height: AppSpacing.lg),
          const _VersionInfo(),
          const SizedBox(height: AppSpacing.lg),
          // Outlined, not filled: leaving is not what this screen is for, and
          // a full-width brand-green button made it the most prominent action
          // on it. The error colour marks it as the exit without shouting —
          // signing out is reversible, so it gets no filled error surface
          // either.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Consumer(
              builder: (context, ref, _) => OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                icon: const Icon(Icons.logout),
                label: Text(l10n.authSignOutAction),
                onPressed: () async {
                  if (await confirmSignOut(context)) await signOut(ref);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// App + connected-server version, for diagnostics and bug reports. The server
/// row is blank until `serverInfoProvider` resolves (or stays blank if it
/// can't be reached) rather than showing a spinner — this is a quiet footnote,
/// not a load-bearing value.
class _VersionInfo extends ConsumerWidget {
  const _VersionInfo();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final appVersion = ref.watch(appVersionProvider).value;
    final serverVersion = ref.watch(serverInfoProvider).value?.version;

    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: Text(l10n.profileAppVersionLabel),
          subtitle: Text(appVersion ?? '—'),
        ),
        ListTile(
          leading: const Icon(Icons.dns_outlined),
          title: Text(l10n.profileServerVersionLabel),
          subtitle: Text(
            serverVersion?.isNotEmpty ?? false ? serverVersion! : '—',
          ),
        ),
      ],
    );
  }
}

/// Opt-in switch for local medication-due reminders (federfall-3uz).
/// Enabling is the moment to ask the OS for notification permission; a denial
/// keeps the toggle off and says why. The subtitle carries the v1 limitation:
/// reminders reconcile when the app runs, so changes made elsewhere lag until
/// the next open.
class _RemindersToggle extends ConsumerWidget {
  const _RemindersToggle();

  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref, {
    required bool enabled,
  }) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    if (enabled) {
      final granted = await ref
          .read(reminderSchedulerProvider)
          .requestPermissions();
      if (!granted) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.remindersPermissionDenied)),
        );
        return;
      }
    }
    await ref
        .read(medicationRemindersEnabledProvider.notifier)
        .set(enabled: enabled);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final enabled = ref.watch(medicationRemindersEnabledProvider);
    return SwitchListTile(
      secondary: const Icon(Icons.notifications_outlined),
      title: Text(l10n.remindersToggleTitle),
      subtitle: Text(l10n.remindersToggleSubtitle),
      value: enabled.value ?? false,
      onChanged: enabled.isLoading
          ? null
          : (v) => _toggle(context, ref, enabled: v),
    );
  }
}

/// Opt-in switch for vet-appointment reminders (federfall-fnpo).
///
/// Separate from [_RemindersToggle] because they are separate wants: dose pings
/// every few hours and a heads-up before a vet visit are not the same kind of
/// interruption, and they land in separate Android channels so the OS can mute
/// one without the other.
class _AppointmentRemindersToggle extends ConsumerWidget {
  const _AppointmentRemindersToggle();

  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref, {
    required bool enabled,
  }) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    if (enabled) {
      final granted = await ref
          .read(reminderSchedulerProvider)
          .requestPermissions();
      if (!granted) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.remindersPermissionDenied)),
        );
        return;
      }
    }
    await ref
        .read(appointmentRemindersEnabledProvider.notifier)
        .set(enabled: enabled);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final enabled = ref.watch(appointmentRemindersEnabledProvider);
    return SwitchListTile(
      secondary: const Icon(Icons.event_outlined),
      title: Text(l10n.appointmentRemindersToggleTitle),
      subtitle: Text(l10n.appointmentRemindersToggleSubtitle),
      value: enabled.value ?? false,
      onChanged: enabled.isLoading
          ? null
          : (v) => _toggle(context, ref, enabled: v),
    );
  }
}

/// The default lead time for appointment reminders (federfall-fnpo). Only shown
/// while appointment reminders are on — a lead time with nothing to lead is
/// noise.
///
/// The choice list deliberately has no "none": that is what the switch above is
/// for, and a switch left on with a default of "none" would produce no
/// reminders with no visible reason. An individual appointment may still opt
/// out, in its own sheet.
class _AppointmentLeadRow extends ConsumerWidget {
  const _AppointmentLeadRow();

  Future<void> _pick(
    BuildContext context,
    WidgetRef ref,
    Duration current,
  ) async {
    final l10n = context.l10n;
    final picked = await showAppSheet<Duration>(
      context,
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.sm,
                ),
                child: Text(
                  l10n.appointmentReminderLeadTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              RadioGroup<Duration>(
                groupValue: current,
                onChanged: (value) => Navigator.of(context).pop(value),
                child: Column(
                  children: [
                    for (final lead in kReminderLeadChoices)
                      RadioListTile<Duration>(
                        value: lead,
                        title: Text(reminderLeadLabel(l10n, lead)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        ),
      ),
    );
    if (picked != null) {
      await ref.read(appointmentReminderLeadProvider.notifier).set(picked);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    if (!(ref.watch(appointmentRemindersEnabledProvider).value ?? false)) {
      return const SizedBox.shrink();
    }
    final lead = ref.watch(appointmentReminderLeadProvider).value;
    return ListTile(
      leading: const Icon(Icons.schedule_outlined),
      title: Text(l10n.appointmentReminderLeadTitle),
      subtitle: Text(l10n.appointmentReminderLeadSubtitle),
      trailing: Text(lead == null ? '' : reminderLeadLabel(l10n, lead)),
      onTap: lead == null ? null : () => _pick(context, ref, lead),
    );
  }
}

/// Configured receipt printer (federfall-i0wq): shows the saved device (or a
/// prompt to set one up), a Test print action, and a way to forget it. Tap
/// the row itself to open the configuration sheet — same "tap to configure"
/// affordance as the rest of this screen's rows.
class _PrinterSection extends ConsumerWidget {
  const _PrinterSection();

  Future<void> _testPrint(
    BuildContext context,
    WidgetRef ref,
    PrinterDeviceRef device,
    ReceiptPaperSize paperSize,
  ) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final service = ref.read(printerServiceProvider);
    try {
      await service.connect(device);
      await service.printTestTicket(l10n.printerTestPrintText, paperSize);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.printerTestPrintSuccess)),
      );
    } on Object catch (e, stackTrace) {
      reportCaughtError(e, stackTrace);
      messenger.showSnackBar(SnackBar(content: Text(errorMessage(l10n, e))));
    } finally {
      await service.disconnect();
    }
  }

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.printerRemoveConfirmTitle),
        content: Text(l10n.printerRemoveConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.actionCancel),
          ),
          DestructiveActionButton(
            label: l10n.printerRemoveAction,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(printerSettingsProvider.notifier).clearDevice();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(printerSettingsProvider).value;
    final device = settings?.device;

    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.print_outlined),
          title: Text(l10n.printerSectionTitle),
          subtitle: Text(
            device != null
                ? '${device.name} · ${printerDeviceDetail(l10n, device)}'
                : l10n.printerNotConfigured,
          ),
          trailing: device == null
              ? null
              : IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: l10n.printerRemoveAction,
                  onPressed: () => _remove(context, ref),
                ),
          onTap: () => showPrinterConfigSheet(context),
        ),
        if (device != null && settings != null)
          Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.md,
              right: AppSpacing.md,
              bottom: AppSpacing.sm,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.receipt_long_outlined),
                label: Text(l10n.printerTestPrintAction),
                onPressed: () =>
                    _testPrint(context, ref, device, settings.paperSize),
              ),
            ),
          ),
      ],
    );
  }
}

/// Opt-in MFA switch (email one-time code as a second factor). Toggles the
/// signed-in user's `mfa_enabled`; the auth-store refresh re-renders the
/// profile with the new value, so the switch reflects [enabled], not local
/// state.
class _MfaToggle extends ConsumerStatefulWidget {
  const _MfaToggle({required this.enabled});

  final bool enabled;

  @override
  ConsumerState<_MfaToggle> createState() => _MfaToggleState();
}

class _MfaToggleState extends ConsumerState<_MfaToggle> {
  bool _busy = false;

  Future<void> _toggle(bool value) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final repo = await ref.read(authRepositoryProvider.future);
      await repo.setMfaEnabled(enabled: value);
    } on Object catch (error, stackTrace) {
      reportCaughtError(error, stackTrace);
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.profileMfaUpdateFailed)),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SwitchListTile(
      secondary: const Icon(Icons.shield_outlined),
      title: Text(l10n.profileMfaTitle),
      subtitle: Text(l10n.profileMfaSubtitle),
      value: widget.enabled,
      onChanged: _busy ? null : _toggle,
    );
  }
}
