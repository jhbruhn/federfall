import 'package:federfall/core/server/server_config_controller.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Email + password sign-in against the configured server (FED-3.1).
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

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

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
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        _error!,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.error),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    PrimaryButton(
                      label: l10n.authSignInAction,
                      isLoading: _busy,
                      onPressed: _signIn,
                    ),
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
