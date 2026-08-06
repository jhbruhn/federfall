import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/routing/app_routes.dart';
import 'package:federfall/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Where an invited member lands from the password-reset email (FED-3.2): they
/// pick a password, which activates their account, then sign in. Reachable
/// without a session (the router gate lets this route through).
class ConfirmResetScreen extends ConsumerStatefulWidget {
  const ConfirmResetScreen({required this.token, super.key});

  /// The reset token carried in the email link's `?token=` query.
  final String? token;

  @override
  ConsumerState<ConfirmResetScreen> createState() => _ConfirmResetScreenState();
}

class _ConfirmResetScreenState extends ConsumerState<ConfirmResetScreen>
    with FormSheetState {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final token = widget.token;
    if (token == null || token.isEmpty) {
      setSaveError(l10n.resetMissingToken);
      return;
    }
    if (!(formKey.currentState?.validate() ?? false)) return;

    // Busy is left set on success: the screen navigates to login next.
    await runSave(() async {
      final repo = await ref.read(authRepositoryProvider.future);
      await repo.confirmPasswordReset(token, _passwordController.text);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.resetSuccess)));
      context.go(AppRoutes.login);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.resetTitle)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(l10n.resetIntro, style: theme.textTheme.bodyMedium),
                    const SizedBox(height: AppSpacing.lg),
                    AppTextField(
                      controller: _passwordController,
                      label: l10n.authPasswordLabel,
                      prefixIcon: Icons.lock_outline,
                      obscureText: true,
                      textInputAction: TextInputAction.next,
                      autofocus: true,
                      enabled: !isBusy,
                      // PocketBase rejects passwords under 8 characters;
                      // catch that client-side with a specific message.
                      validator: Validators.compose([
                        Validators.required(l10n),
                        Validators.minLength(l10n, 8),
                      ]),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppTextField(
                      controller: _confirmController,
                      label: l10n.resetConfirmLabel,
                      prefixIcon: Icons.lock_outline,
                      obscureText: true,
                      textInputAction: TextInputAction.go,
                      enabled: !isBusy,
                      validator: (v) => v != _passwordController.text
                          ? l10n.resetMismatch
                          : null,
                    ),
                    if (saveError != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        saveError!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    PrimaryButton(
                      label: l10n.actionSave,
                      icon: Icons.check,
                      isLoading: isBusy,
                      onPressed: _submit,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
