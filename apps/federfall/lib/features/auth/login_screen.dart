import 'package:federfall/core/auth/sign_out.dart';
import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/core/server/server_config_controller.dart';
import 'package:federfall/core/server/server_info.dart';
import 'package:federfall/core/server/server_info_provider.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/auth/oauth_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

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
  final _otpController = TextEditingController();

  bool _busy = false;
  String? _error;

  // OAuth wait state: the external browser flow can be abandoned (the future
  // then never completes), so while it is pending the screen offers a cancel
  // action. Cancelling bumps the attempt counter, which orphans the pending
  // wait — its eventual completion is ignored instead of touching state.
  bool _oauthPending = false;
  int _oauthAttempt = 0;

  // MFA second step: set once a password succeeds on an MFA-enabled account.
  // While non-null the form shows the one-time-code field instead of password.
  String? _mfaId;
  String? _otpId;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _otpController.dispose();
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
    } on MfaRequiredException catch (e) {
      // Password was correct but the account needs a second factor: send the
      // one-time code and switch the form to the OTP step.
      try {
        final repo = await ref.read(authRepositoryProvider.future);
        final otpId = await repo.requestOtp(_emailController.text.trim());
        if (!mounted) return;
        setState(() {
          _busy = false;
          _mfaId = e.mfaId;
          _otpId = otpId;
        });
      } on Object catch (error, stackTrace) {
        reportCaughtError(error, stackTrace);
        if (!mounted) return;
        setState(() {
          _busy = false;
          _error = l10n.errorGenericTitle;
        });
      }
    } on RepositoryException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _messageFor(l10n, e);
      });
    } on Object catch (error, stackTrace) {
      reportCaughtError(error, stackTrace);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = l10n.errorGenericTitle;
      });
    }
  }

  Future<void> _signInWithProvider(OAuthProvider provider) async {
    final l10n = context.l10n;
    final attempt = ++_oauthAttempt;
    setState(() {
      _busy = true;
      _oauthPending = true;
      _error = null;
    });
    try {
      final repo = await ref.read(authRepositoryProvider.future);
      // Opens the provider URL externally; the flow completes over PocketBase's
      // realtime channel and the auth-store change drives the router gate (to
      // /home, or /pending for a freshly self-registered guest).
      await repo.signInWithOAuth2(
        provider.name,
        (url) => launchUrl(url, mode: LaunchMode.externalApplication),
      );
    } on Object catch (error, stackTrace) {
      reportCaughtError(error, stackTrace);
      if (!mounted || attempt != _oauthAttempt) return;
      setState(() {
        _busy = false;
        _oauthPending = false;
        _error = l10n.authOauthFailed;
      });
    }
  }

  /// Unlocks the screen from an abandoned OAuth wait. A flow that still
  /// completes in the browser afterwards signs in regardless — the auth-store
  /// change drives the router gate, not this screen.
  void _cancelOAuth() {
    _oauthAttempt++;
    setState(() {
      _busy = false;
      _oauthPending = false;
    });
  }

  Future<void> _verifyOtp() async {
    final l10n = context.l10n;
    final otpId = _otpId;
    final mfaId = _mfaId;
    if (otpId == null || mfaId == null) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final repo = await ref.read(authRepositoryProvider.future);
      await repo.authWithOtp(
        otpId: otpId,
        code: _otpController.text.trim(),
        mfaId: mfaId,
      );
      // Success: the auth-store change drives the router gate to /home.
    } on RepositoryException {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = l10n.authOtpInvalid;
      });
    } on Object catch (error, stackTrace) {
      reportCaughtError(error, stackTrace);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = l10n.errorGenericTitle;
      });
    }
  }

  /// Escape hatch from the OTP step (federfall-8r9): back to the password
  /// form, e.g. for a typo'd email whose code will never arrive. The entered
  /// password is kept so retrying is one tap.
  void _backToPassword() {
    _otpController.clear();
    setState(() {
      _mfaId = null;
      _otpId = null;
      _error = null;
    });
  }

  /// Requests a fresh one-time code for the same sign-in. The new [_otpId]
  /// replaces the old one, so only the latest code verifies.
  Future<void> _resendOtp() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = await ref.read(authRepositoryProvider.future);
      final otpId = await repo.requestOtp(_emailController.text.trim());
      if (!mounted) return;
      setState(() {
        _busy = false;
        _otpId = otpId;
      });
      messenger.showSnackBar(SnackBar(content: Text(l10n.authOtpResent)));
    } on Object catch (error, stackTrace) {
      reportCaughtError(error, stackTrace);
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

  /// Also purges the protected-file cache: the cached images belong to the
  /// server (and account) being left behind — same rationale as [signOut].
  Future<void> _switchServer() {
    purgeProtectedFileCache(
      ref.read(protectedFileCacheManagerProvider).emptyCache,
    );
    return ref.read(serverConfigControllerProvider.notifier).clearServerUrl();
  }

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
    // Once a password has cleared on an MFA account, the form becomes the
    // one-time-code step and the password/email/reset controls step aside.
    final otpStep = _mfaId != null;

    return Scaffold(
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
                    // Brand-first header: the app name and a warm tagline lead,
                    // so the screen reads as considered, not a bare admin form.
                    // (A proper logo mark is a separate task.)
                    Text(
                      l10n.appName,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      l10n.authTagline,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    // The verified server's name, demoted to a subtitle now the
                    // app name carries the header.
                    if (info != null && info.name.isNotEmpty) ...[
                      Text(
                        l10n.authSignInToServer(info.name),
                        style: theme.textTheme.titleMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                    ],
                    if (otpStep) ...[
                      Text(
                        l10n.authOtpTitle,
                        style: theme.textTheme.titleMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        l10n.authOtpDescription,
                        style: theme.textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      AppTextField(
                        controller: _otpController,
                        label: l10n.authOtpLabel,
                        prefixIcon: Icons.pin_outlined,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.go,
                        autofocus: true,
                        enabled: !_busy,
                        validator: Validators.required(l10n),
                        onSubmitted: (_) => _busy ? null : _verifyOtp(),
                      ),
                    ],
                    if (!otpStep && auth.password) ...[
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
                    if (otpStep) ...[
                      const SizedBox(height: AppSpacing.lg),
                      PrimaryButton(
                        label: l10n.authOtpVerifyAction,
                        isLoading: _busy,
                        onPressed: _verifyOtp,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      TextButton(
                        onPressed: _busy ? null : _resendOtp,
                        child: Text(l10n.authOtpResendAction),
                      ),
                      TextButton(
                        onPressed: _busy ? null : _backToPassword,
                        child: Text(l10n.authOtpBackAction),
                      ),
                    ] else if (auth.password) ...[
                      const SizedBox(height: AppSpacing.lg),
                      PrimaryButton(
                        label: l10n.authSignInAction,
                        isLoading: _busy,
                        onPressed: _signIn,
                      ),
                    ],
                    // Only offered when the server can actually send the email.
                    if (!otpStep && auth.passwordReset) ...[
                      const SizedBox(height: AppSpacing.xs),
                      TextButton(
                        onPressed: _busy ? null : _requestReset,
                        child: Text(l10n.authResetLinkAction),
                      ),
                    ],
                    // OAuth2: one button per configured provider. Shown outside
                    // the OTP step; the divider appears only when password
                    // sign-in is also on (else these are the only options).
                    if (!otpStep && auth.oauth2.isNotEmpty) ...[
                      if (auth.password) ...[
                        const SizedBox(height: AppSpacing.md),
                        _OrDivider(label: l10n.authOrSeparator),
                      ],
                      ..._oauthButtons(),
                      // The external flow can be abandoned in the browser and
                      // its future then never completes — offer a way out so
                      // the screen doesn't stay locked until an app restart.
                      if (_oauthPending) ...[
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          l10n.authOauthWaiting,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        TextButton(
                          onPressed: _cancelOAuth,
                          child: Text(l10n.actionCancel),
                        ),
                      ],
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

  /// One sign-in button per configured OAuth2 provider. The provider list loads
  /// asynchronously; while it resolves (or if it fails) nothing is shown — the
  /// server has already told us providers exist via serverInfo, so this only
  /// fills in their labels.
  List<Widget> _oauthButtons() {
    final l10n = context.l10n;
    final providers = ref.watch(oauthProvidersProvider).value ?? const [];
    return [
      for (final p in providers) ...[
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _signInWithProvider(p),
          icon: const Icon(Icons.login),
          label: Text(l10n.authContinueWith(p.displayName)),
        ),
      ],
    ];
  }
}

/// A horizontal rule with a centered label ("or"), separating password sign-in
/// from the OAuth2 provider buttons.
class _OrDivider extends StatelessWidget {
  const _OrDivider({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const Expanded(child: Divider()),
      ],
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
    } on Object catch (error, stackTrace) {
      reportCaughtError(error, stackTrace);
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
