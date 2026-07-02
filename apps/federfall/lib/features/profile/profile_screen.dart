import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/auth/roles.dart';
import 'package:federfall/core/auth/sign_out.dart';
import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/profile/edit_profile_sheet.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
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

    return Scaffold(
      appBar: AppBar(
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
          const SizedBox(height: AppSpacing.lg),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Consumer(
              builder: (context, ref, _) => PrimaryButton(
                label: l10n.authSignOutAction,
                icon: Icons.logout,
                onPressed: () => signOut(ref),
              ),
            ),
          ),
        ],
      ),
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
