import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/auth/roles.dart';
import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/profile/edit_profile_sheet.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Signs the user out. Clearing the store flips authStatus → the router gate
/// routes back to /login.
Future<void> signOut(WidgetRef ref) async {
  final repo = await ref.read(authRepositoryProvider.future);
  repo.signOut();
}

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
        errorMessage: (e) => errorMessage(l10n, e),
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

    return ListView(
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
    );
  }
}
