import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Authenticated app shell / landing. Placeholder for FED-2.4; role-gated
/// navigation and the dashboard arrive in FED-3.3 / Phase 7. For the walking
/// skeleton it confirms the session by showing the signed-in user and a way to
/// sign out.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _signOut(WidgetRef ref) async {
    final repo = await ref.read(authRepositoryProvider.future);
    // Clearing the store flips authStatus → the gate routes back to /login.
    repo.signOut();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final user = ref.watch(currentUserProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appName),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: l10n.authSignOutAction,
            onPressed: () => _signOut(ref),
          ),
        ],
      ),
      body: Center(child: Text(user?.name ?? user?.email ?? l10n.appName)),
    );
  }
}
