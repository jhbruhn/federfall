import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Lets the signed-in user edit their own name and phone (UX Phase B). The
/// access rule permits self-edit of just these fields. Resolves to `true` on
/// save so the caller can refresh.
Future<bool?> showEditProfileSheet(BuildContext context, AppUser user) {
  return showAppSheet<bool>(
    context,
    builder: (_) => EditProfileSheet(user: user),
  );
}

class EditProfileSheet extends ConsumerStatefulWidget {
  const EditProfileSheet({required this.user, super.key});

  final AppUser user;

  @override
  ConsumerState<EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends ConsumerState<EditProfileSheet>
    with DiscardGuard, FormSheetState {
  late final TextEditingController _name;
  late final TextEditingController _phone;

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
    if (!(formKey.currentState?.validate() ?? false)) return;
    final navigator = Navigator.of(context);

    final ok = await runSave(() async {
      final repo = await ref.read(authRepositoryProvider.future);
      await repo.updateProfile(name: _name.text, phone: _phone.text);
      ref.invalidate(currentUserProvider);
    });
    if (ok && mounted) navigator.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return guardUnsavedChanges(
      child: SheetScaffold(
        title: l10n.profileEditTitle,
        formKey: formKey,
        onFormChanged: markDirty,
        isBusy: isBusy,
        error: saveError,
        onSave: _save,
        children: [
          AppTextField(
            controller: _name,
            label: l10n.profileNameLabel,
            prefixIcon: Icons.badge_outlined,
            textInputAction: TextInputAction.next,
            enabled: !isBusy,
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _phone,
            label: l10n.profilePhoneLabel,
            prefixIcon: Icons.phone_outlined,
            keyboardType: TextInputType.phone,
            enabled: !isBusy,
          ),
        ],
      ),
    );
  }
}
