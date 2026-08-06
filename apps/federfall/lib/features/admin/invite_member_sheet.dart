import 'dart:async';

import 'package:federfall/core/auth/roles.dart';
import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the invite form (FED-3.2). The supervisor creates a member's account
/// and PocketBase emails them a password-reset link to activate it. Resolves to
/// `true` once an invite is sent so the caller can refresh the roster.
Future<bool?> showInviteMemberSheet(BuildContext context) {
  return showAppSheet<bool>(
    context,
    builder: (_) => const InviteMemberSheet(),
  );
}

class InviteMemberSheet extends ConsumerStatefulWidget {
  const InviteMemberSheet({super.key});

  @override
  ConsumerState<InviteMemberSheet> createState() => _InviteMemberSheetState();
}

class _InviteMemberSheetState extends ConsumerState<InviteMemberSheet>
    with DiscardGuard, FormSheetState {
  final _emailController = TextEditingController();
  final _nameController = TextEditingController();

  UserRole _role = UserRole.carer;

  @override
  void dispose() {
    _emailController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _invite() async {
    if (!(formKey.currentState?.validate() ?? false)) return;
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final email = _emailController.text.trim();

    // Both outcomes below close the sheet themselves, so nothing pops after
    // `runSave` returns — the InviteEmailFailed path is a SUCCESS with a
    // caveat, not a failure to report in the error slot.
    await runSave(() async {
      final repo = await ref.read(authRepositoryProvider.future);
      try {
        await repo.inviteUser(
          email: email,
          role: _role,
          name: _nameController.text,
        );
      } on InviteEmailFailedException {
        // The account exists — only the reset email failed. Close (so the
        // roster shows the new member) and offer to resend instead of implying
        // the whole invite failed; retrying the invite hits "email taken".
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(
            content: Text(l10n.inviteEmailFailed(email)),
            duration: const Duration(seconds: 8),
            action: SnackBarAction(
              label: l10n.inviteResendAction,
              // The sheet is popped by then: use only captured objects.
              onPressed: () =>
                  unawaited(_resendResetEmail(repo, email, messenger, l10n)),
            ),
          ),
        );
        navigator.pop(true);
        return;
      }
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.inviteSent(email))));
      navigator.pop(true);
    });
  }

  /// Resends the invite's password-reset email from the failure snackbar.
  /// Runs after the sheet is closed, so it must not touch `context`/`ref` —
  /// everything it needs is passed in.
  Future<void> _resendResetEmail(
    AuthRepository repo,
    String email,
    ScaffoldMessengerState messenger,
    AppLocalizations l10n,
  ) async {
    try {
      await repo.requestPasswordReset(email);
      messenger.showSnackBar(SnackBar(content: Text(l10n.inviteSent(email))));
    } on RepositoryException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(errorMessage(l10n, e))));
    } on Object catch (error, stackTrace) {
      reportCaughtError(error, stackTrace);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return guardUnsavedChanges(
      child: SheetScaffold(
        title: l10n.inviteSectionTitle,
        formKey: formKey,
        onFormChanged: markDirty,
        isBusy: isBusy,
        error: saveError,
        onSave: _invite,
        saveLabel: l10n.inviteAction,
        saveIcon: Icons.send,
        children: [
          AppTextField(
            controller: _emailController,
            label: l10n.authEmailLabel,
            prefixIcon: Icons.alternate_email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            enabled: !isBusy,
            validator: Validators.compose([
              Validators.required(l10n),
              Validators.email(l10n),
            ]),
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _nameController,
            label: l10n.inviteNameLabel,
            prefixIcon: Icons.badge_outlined,
            textInputAction: TextInputAction.done,
            enabled: !isBusy,
          ),
          const SizedBox(height: AppSpacing.md),
          DropdownButtonFormField<UserRole>(
            initialValue: _role,
            decoration: InputDecoration(
              labelText: l10n.profileRoleLabel,
              prefixIcon: const Icon(Icons.security_outlined),
            ),
            items: [
              for (final r in UserRole.values)
                DropdownMenuItem(value: r, child: Text(userRoleLabel(l10n, r))),
            ],
            onChanged: isBusy
                ? null
                : (r) => setState(() => _role = r ?? _role),
          ),
        ],
      ),
    );
  }
}
