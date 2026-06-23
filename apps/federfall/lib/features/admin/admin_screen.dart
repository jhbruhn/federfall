import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/auth/roles.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Supervisor-only admin area (FED-3.3 stub). Team management and invites
/// (FED-3.2) land here. Reached only via the supervisor-gated entry on home,
/// but it re-checks the role so a typed-in URL degrades gracefully — the real
/// boundary remains the server API rules (FED-1.11).
class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final role = ref.watch(currentUserProvider).value?.role;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.adminTitle)),
      body: canManageTeam(role)
          ? EmptyView(
              icon: Icons.groups_outlined,
              message: l10n.adminPlaceholder,
            )
          : EmptyView(
              icon: Icons.lock_outline,
              message: l10n.errorUnauthorized,
            ),
    );
  }
}
