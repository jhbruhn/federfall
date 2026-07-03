import 'package:federfall/config/app_environment.dart';
import 'package:federfall/core/server/server_config_controller.dart';
import 'package:federfall/core/server/server_probe.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Native-only first-run screen where the user enters their Federfall server
/// URL (FED-3.0). The address is normalised, probed against
/// `/api/federfall/info` and, on success, persisted — at which point the router
/// gate moves on to login.
///
/// On web this screen is never reached: the base URL is the serving origin, so
/// the config is always resolved and the gate never redirects here.
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _formKey = GlobalKey<FormState>();
  // Prefilled with the build-time POCKETBASE_URL override when present, so a
  // dev build lands on setup with the local backend already typed in (the
  // override never auto-configures the server — see ServerConfigController).
  final _controller = TextEditingController(
    text: AppEnvironment.pocketbaseUrlOverride,
  );

  bool _busy = false;

  /// Probe failure to show inline; cleared on each new attempt.
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final l10n = context.l10n;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    final result = await ref.read(serverProbeProvider).probe(_controller.text);
    if (!mounted) return;

    switch (result) {
      case ProbeReachable(:final baseUrl):
        // Persisting flips the server config to "configured"; the router's
        // redirect gate then routes us on to /login. No manual nav needed.
        await ref
            .read(serverConfigControllerProvider.notifier)
            .setServerUrl(baseUrl);
        return;
      case ProbeInvalidUrl():
        setState(() {
          _busy = false;
          _error = l10n.fieldInvalidUrl;
        });
      case ProbeInsecureHttp():
        setState(() {
          _busy = false;
          _error = l10n.serverInsecureHttp;
        });
      case ProbeUnreachable():
        setState(() {
          _busy = false;
          _error = l10n.serverUnreachable;
        });
      case ProbeNotFederfall():
        setState(() {
          _busy = false;
          _error = l10n.serverNotFederfall;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.serverSetupTitle)),
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
                    Text(
                      l10n.serverSetupDescription,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    AppTextField(
                      controller: _controller,
                      label: l10n.serverUrlLabel,
                      hintText: 'https://federfall.example.org',
                      prefixIcon: Icons.dns_outlined,
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.go,
                      autofocus: true,
                      enabled: !_busy,
                      // Only the empty check runs here; URL validity is left
                      // to the probe, which accepts scheme-less input (it
                      // assumes https) and reports malformed addresses inline.
                      validator: Validators.required(l10n),
                      onChanged: (_) {
                        if (_error != null) setState(() => _error = null);
                      },
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
                      label: l10n.serverConnectAction,
                      icon: Icons.arrow_forward,
                      isLoading: _busy,
                      onPressed: _connect,
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
