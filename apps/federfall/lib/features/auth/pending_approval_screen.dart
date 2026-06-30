import 'package:federfall/core/auth/auth_status.dart';
import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shown to a self-registered guest whose account has no role yet: they are
/// signed in but the server walls them off from all data until a supervisor
/// promotes them (federfall-49l.3). The router gate keeps guests here and off
/// the app shell. "Check again" refreshes the session so a just-promoted user
/// drops straight through to the app; "Sign out" clears the session.
class PendingApprovalScreen extends ConsumerStatefulWidget {
  const PendingApprovalScreen({super.key});

  @override
  ConsumerState<PendingApprovalScreen> createState() =>
      _PendingApprovalScreenState();
}

class _PendingApprovalScreenState extends ConsumerState<PendingApprovalScreen> {
  bool _busy = false;

  Future<void> _checkAgain() async {
    setState(() => _busy = true);
    try {
      final repo = await ref.read(authRepositoryProvider.future);
      await repo.refresh();
      // The gate re-runs off these; a promoted user is routed to the app.
      ref
        ..invalidate(currentUserProvider)
        ..invalidate(authStatusProvider);
    } on Object catch (error, stackTrace) {
      reportCaughtError(error, stackTrace);
      // Stay put; the message already explains the state.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    final repo = await ref.read(authRepositoryProvider.future);
    repo.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final email = ref.watch(currentUserProvider).value?.email;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.hourglass_top_outlined,
                    size: 48,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    l10n.pendingTitle,
                    style: theme.textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    l10n.pendingDescription,
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  if (email != null && email.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      email,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  PrimaryButton(
                    label: l10n.pendingCheckAgainAction,
                    icon: Icons.refresh,
                    isLoading: _busy,
                    onPressed: _checkAgain,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  TextButton(
                    onPressed: _busy ? null : _signOut,
                    child: Text(l10n.authSignOutAction),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
