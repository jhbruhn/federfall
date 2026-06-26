import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/auth/roles.dart';
import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/admin/org_settings_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Supervisor-only org settings (UX Phase A): contact details and the
/// finder-PII retention window. Re-checks the role so a typed-in URL degrades
/// gracefully — the server rules remain the real boundary.
class OrgSettingsScreen extends ConsumerWidget {
  const OrgSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final role = ref.watch(currentUserProvider).value?.role;

    if (!canManageTeam(role)) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.orgSettingsTitle)),
        body: EmptyView(
          icon: Icons.lock_outline,
          message: l10n.errorUnauthorized,
        ),
      );
    }

    final org = ref.watch(currentOrganisationProvider);

    return Scaffold(
      appBar: AppBar(
        // No up arrow when shown as the right pane of the admin two-pane.
        automaticallyImplyLeading: !context.isExpanded,
        title: Text(l10n.orgSettingsTitle),
      ),
      body: AsyncValueView<Organisation>(
        value: org,
        onRetry: () => ref.invalidate(currentOrganisationProvider),
        errorMessage: (e) => errorMessage(l10n, e),
        data: _OrgForm.new,
      ),
    );
  }
}

class _OrgForm extends ConsumerStatefulWidget {
  const _OrgForm(this.org);

  final Organisation org;

  @override
  ConsumerState<_OrgForm> createState() => _OrgFormState();
}

class _OrgFormState extends ConsumerState<_OrgForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late final TextEditingController _retention;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final o = widget.org;
    _name = TextEditingController(text: o.name);
    _email = TextEditingController(text: o.contactEmail ?? '');
    _phone = TextEditingController(text: o.contactPhone ?? '');
    final months = switch (o.settings[finderRetentionMonthsKey]) {
      final int v => v,
      final num v => v.toInt(),
      _ => defaultFinderRetentionMonths,
    };
    _retention = TextEditingController(text: '$months');
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _retention.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    final months =
        int.tryParse(_retention.text.trim()) ?? defaultFinderRetentionMonths;
    try {
      final repo = await ref.read(organisationsRepositoryProvider.future);
      await repo.update(widget.org.id, {
        'name': _name.text.trim(),
        'contact_email': _email.text.trim(),
        'contact_phone': _phone.text.trim(),
        'settings': {
          ...widget.org.settings,
          finderRetentionMonthsKey: months,
        },
      });
      ref.invalidate(currentOrganisationProvider);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.orgSettingsSaved)));
      setState(() => _busy = false);
    } on RepositoryException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = errorMessage(l10n, e);
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = l10n.errorGenericTitle;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppTextField(
                    controller: _name,
                    label: l10n.orgNameLabel,
                    prefixIcon: Icons.apartment_outlined,
                    enabled: !_busy,
                    validator: Validators.required(l10n),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppTextField(
                    controller: _email,
                    label: l10n.orgContactEmailLabel,
                    prefixIcon: Icons.alternate_email,
                    keyboardType: TextInputType.emailAddress,
                    enabled: !_busy,
                    validator: Validators.email(l10n),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppTextField(
                    controller: _phone,
                    label: l10n.orgContactPhoneLabel,
                    prefixIcon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                    enabled: !_busy,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    l10n.orgRetentionSectionTitle,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AppTextField(
                    controller: _retention,
                    label: l10n.orgRetentionMonthsLabel,
                    prefixIcon: Icons.gavel_outlined,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    enabled: !_busy,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      l10n.orgRetentionHelp,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      _error!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  PrimaryButton(
                    label: l10n.actionSave,
                    icon: Icons.check,
                    isLoading: _busy,
                    onPressed: _save,
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
