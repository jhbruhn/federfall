import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Lets the signed-in user edit their own name and phone (UX Phase B). The
/// access rule permits self-edit of just these fields. Resolves to `true` on
/// save so the caller can refresh.
Future<bool?> showEditProfileSheet(BuildContext context, AppUser user) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => EditProfileSheet(user: user),
  );
}

class EditProfileSheet extends ConsumerStatefulWidget {
  const EditProfileSheet({required this.user, super.key});

  final AppUser user;

  @override
  ConsumerState<EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends ConsumerState<EditProfileSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.user.name ?? '');
    _phone = TextEditingController(text: widget.user.phone ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final navigator = Navigator.of(context);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = await ref.read(authRepositoryProvider.future);
      await repo.updateProfile(name: _name.text, phone: _phone.text);
      ref.invalidate(currentUserProvider);
      if (!mounted) return;
      navigator.pop(true);
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
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          top: AppSpacing.sm,
          bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.profileEditTitle, style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                controller: _name,
                label: l10n.profileNameLabel,
                prefixIcon: Icons.badge_outlined,
                textInputAction: TextInputAction.next,
                enabled: !_busy,
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                controller: _phone,
                label: l10n.profilePhoneLabel,
                prefixIcon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
                enabled: !_busy,
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
              const SizedBox(height: AppSpacing.md),
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
    );
  }
}
