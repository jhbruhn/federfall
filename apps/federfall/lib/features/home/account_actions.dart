import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/auth/roles.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/routing/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// App-bar actions reachable from every top-level destination: the supervisor
/// admin area (role-gated) and the signed-in user's profile. Packaged as a
/// single [AppBar.actions] entry so each shell tab can share one source.
class AccountActions extends ConsumerWidget {
  const AccountActions({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final role = ref.watch(currentUserProvider).value?.role;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (canManageTeam(role))
          IconButton(
            icon: const Icon(Icons.manage_accounts_outlined),
            tooltip: l10n.adminTitle,
            onPressed: () => context.push(AppRoutes.admin),
          ),
        IconButton(
          icon: const Icon(Icons.account_circle_outlined),
          tooltip: l10n.profileTitle,
          onPressed: () => context.push(AppRoutes.profile),
        ),
      ],
    );
  }
}
