import 'package:federfall/core/server/server_config_controller.dart';
import 'package:federfall/core/server/server_info.dart';
import 'package:federfall/core/server/server_info_provider.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Email + password sign-in against the configured server (FED-3.1).
///
/// The form adapts to the verified server's capabilities (federfall-7nf.1):
/// the server's name heads the screen, password fields show only when password
/// auth is enabled, and the "forgot password" link appears only when the
/// server can actually send reset email. The router gate ensures those
/// capabilities have resolved before this screen renders.
///
/// On success the PocketBase auth store gains a token; `authStatusProvider`
/// observes that change and the router gate moves on to the home shell, so this
/// screen never navigates by hand. On native a "switch server" action clears
/// the configured URL and drops back to the setup gate.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final l10n = context.l10n;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final repo = await ref.read(authRepositoryProvider.future);
      await repo.signIn(
        _emailController.text.trim(),
        _passwordController.text,
      );
      // Success: the auth-store change drives the router gate to /home; leave
      // the spinner up while we are redirected away.
    } on RepositoryException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _messageFor(l10n, e);
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = l10n.errorGenericTitle;
      });
    }
  }

  /// Login-specific copy: a rejected password is a 400/401/403 here, which
  /// should read as "wrong credentials" rather than the generic validation /
  /// authorization wording.
  String _messageFor(AppLocalizations l10n, RepositoryException e) {
    return switch (e.kind) {
      RepositoryErrorKind.network => l10n.errorOffline,
      RepositoryErrorKind.validation ||
      RepositoryErrorKind.unauthorized =>
        l10n.authInvalidCredentials,
      _ => l10n.errorGenericTitle,
    };
  }

  Future<void> _switchServer() =>
      ref.read(serverConfigControllerProvider.notifier).clearServerUrl();

  Future<void> _requestReset() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final sent = await showDialog<bool>(
      context: context,
      builder: (_) => _ResetPasswordDialog(initialEmail: _emailController.text),
    );
    if (sent ?? false) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.authResetSent)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    // Capabilities of the verified server; null falls back to the default set
    // (password sign-in, no reset link) so the screen still works if discovery
    // failed.
    final info = ref.watch(serverInfoProvider).value;
    final auth = info?.auth ?? const ServerAuthOptions();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.authLoginTitle)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (info != null && info.name.isNotEmpty) ...[
                      Text(
                        l10n.authSignInToServer(info.name),
                        style: theme.textTheme.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                    ],
                    if (auth.password) ...[
                      AppTextField(
                        controller: _emailController,
                        label: l10n.authEmailLabel,
                        prefixIcon: Icons.alternate_email,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofocus: true,
                        enabled: !_busy,
                        validator: Validators.compose([
                          Validators.required(l10n),
                          Validators.email(l10n),
                        ]),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      AppTextField(
                        controller: _passwordController,
                        label: l10n.authPasswordLabel,
                        prefixIcon: Icons.lock_outline,
                        obscureText: true,
                        textInputAction: TextInputAction.go,
                        enabled: !_busy,
                        validator: Validators.required(l10n),
                        // Enter on the password field submits the form.
                        onSubmitted: (_) => _busy ? null : _signIn(),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        _error!,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.error),
                      ),
                    ],
                    if (auth.password) ...[
                      const SizedBox(height: AppSpacing.lg),
                      PrimaryButton(
                        label: l10n.authSignInAction,
                        isLoading: _busy,
                        onPressed: _signIn,
                      ),
                    ],
                    // Only offered when the server can actually send the email.
                    if (auth.passwordReset) ...[
                      const SizedBox(height: AppSpacing.xs),
                      TextButton(
                        onPressed: _busy ? null : _requestReset,
                        child: Text(l10n.authResetLinkAction),
                      ),
                    ],
                    // Native only: web is pinned to its serving origin, so
                    // there is no server to switch.
                    if (!kIsWeb) ...[
                      const SizedBox(height: AppSpacing.sm),
                      TextButton(
                        onPressed: _busy ? null : _switchServer,
                        child: Text(l10n.serverSwitchAction),
                      ),
                    ],
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

/// Collects an email and requests a password-reset link. Pops `true` once the
/// request has been sent so the caller can confirm; the wording never reveals
/// whether an account actually exists for the address.
class _ResetPasswordDialog extends ConsumerStatefulWidget {
  const _ResetPasswordDialog({required this.initialEmail});

  final String initialEmail;

  @override
  ConsumerState<_ResetPasswordDialog> createState() =>
      _ResetPasswordDialogState();
}

class _ResetPasswordDialogState extends ConsumerState<_ResetPasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _controller = TextEditingController(text: widget.initialEmail);
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);

    // Always report success regardless of the outcome: surfacing a failure
    // would leak whether the address has an account.
    try {
      final repo = await ref.read(authRepositoryProvider.future);
      await repo.requestPasswordReset(_controller.text.trim());
    } on Object {
      // Swallowed deliberately (see above).
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.authResetTitle),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.authResetDescription),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              controller: _controller,
              label: l10n.authEmailLabel,
              prefixIcon: Icons.alternate_email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.go,
              autofocus: true,
              enabled: !_busy,
              validator: Validators.compose([
                Validators.required(l10n),
                Validators.email(l10n),
              ]),
              onSubmitted: (_) => _busy ? null : _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(l10n.authResetSendAction),
        ),
      ],
    );
  }
}
