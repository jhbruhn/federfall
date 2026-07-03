import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/auth/roles.dart';
import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the member management sheet (UX Phase A): change a member's role,
/// activate/deactivate, or remove them. Resolves to `true` if anything changed
/// so the caller can refresh the roster. A supervisor cannot edit their own
/// account here — that guards against demoting or locking out the last
/// supervisor (you always remain active).
Future<bool?> showMemberManagementSheet(
  BuildContext context,
  AppUser member,
) {
  return showAppSheet<bool>(
    context,
    builder: (_) => MemberManagementSheet(member: member),
  );
}

class MemberManagementSheet extends ConsumerStatefulWidget {
  const MemberManagementSheet({required this.member, super.key});

  final AppUser member;

  @override
  ConsumerState<MemberManagementSheet> createState() =>
      _MemberManagementSheetState();
}

class _MemberManagementSheetState extends ConsumerState<MemberManagementSheet>
    with DiscardGuard {
  late UserRole _role;
  late bool _active;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _role = widget.member.role ?? UserRole.carer;
    _active = widget.member.isActive;
  }

  bool get _isSelf =>
      ref.read(currentUserProvider).value?.id == widget.member.id;

  Future<PbUsersRepository> get _repo =>
      ref.read(usersRepositoryProvider.future);

  Future<void> _save() async {
    final l10n = context.l10n;
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = await _repo;
      await repo.update(widget.member.id, {
        'role': _role.wire,
        'is_active': _active,
      });
      if (!mounted) return;
      navigator.pop(true);
    } on RepositoryException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = errorMessage(l10n, e);
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

  Future<void> _remove() async {
    final l10n = context.l10n;
    final navigator = Navigator.of(context);
    final name = _label();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Removal must respect the member's open caseload: deleting the active
      // carer of open cases would leave them pointing at a deleted user with
      // nobody responsible — the supervisor has to hand them over first
      // (federfall-xxi). The server's delete hook enforces this invariant
      // (federfall-zdcb); this pre-check just gives a friendlier dialog than
      // the raw error.
      final casesRepo = await ref.read(casesRepositoryProvider.future);
      final openCases = (await casesRepo.forCarer(
        widget.member.id,
      )).where((c) => c.status != CaseStatus.disposed).length;
      if (!mounted) return;
      setState(() => _busy = false);
      if (openCases > 0) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l10n.memberRemoveAction),
            content: Text(l10n.memberRemoveBlockedOpenCases(openCases, name)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(l10n.actionOk),
              ),
            ],
          ),
        );
        return;
      }
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.memberRemoveAction),
          content: Text(l10n.memberRemoveConfirm(name)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.actionCancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.memberRemoveAction),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      setState(() {
        _busy = true;
        _error = null;
      });
      final repo = await _repo;
      await repo.delete(widget.member.id);
      if (!mounted) return;
      navigator.pop(true);
    } on RepositoryException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = errorMessage(l10n, e);
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

  String _label() {
    final name = widget.member.name;
    return name != null && name.isNotEmpty ? name : widget.member.email;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final disabled = _busy || _isSelf;

    return guardUnsavedChanges(
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            top: AppSpacing.sm,
            bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_label(), style: theme.textTheme.titleMedium),
              Text(
                widget.member.email,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (_isSelf) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  l10n.memberSelfNote,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<UserRole>(
                initialValue: _role,
                decoration: InputDecoration(
                  labelText: l10n.profileRoleLabel,
                  prefixIcon: const Icon(Icons.security_outlined),
                ),
                items: [
                  for (final r in UserRole.values)
                    DropdownMenuItem(
                      value: r,
                      child: Text(userRoleLabel(l10n, r)),
                    ),
                ],
                onChanged: disabled
                    ? null
                    : (r) {
                        setState(() => _role = r ?? _role);
                        markDirty();
                      },
              ),
              const SizedBox(height: AppSpacing.sm),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.memberActiveLabel),
                value: _active,
                onChanged: disabled
                    ? null
                    : (v) {
                        setState(() => _active = v);
                        markDirty();
                      },
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
                onPressed: disabled ? null : _save,
              ),
              if (!_isSelf) ...[
                const SizedBox(height: AppSpacing.sm),
                TextButton.icon(
                  onPressed: _busy ? null : _remove,
                  icon: Icon(
                    Icons.person_remove_outlined,
                    color: theme.colorScheme.error,
                  ),
                  label: Text(
                    l10n.memberRemoveAction,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
