import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/cases_labels.dart';
import 'package:federfall/features/cases/placements/placements_providers.dart';
import 'package:federfall/features/cases/sharing/sharing_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the case-sharing sheet (FED-5.1): list current opt-in shares, grant a
/// new one (read/edit) to an org member, change an existing share's access
/// level, or revoke (with confirmation). Only offered to the active carer or a
/// supervisor (the server create rule enforces it too).
Future<void> showCaseShareSheet(
  BuildContext context, {
  required String caseId,
  required String? activeCarer,
}) => showAppSheet<void>(
  context,
  builder: (_) => _CaseShareSheet(caseId: caseId, activeCarer: activeCarer),
);

class _CaseShareSheet extends ConsumerStatefulWidget {
  const _CaseShareSheet({required this.caseId, required this.activeCarer});

  final String caseId;
  final String? activeCarer;

  @override
  ConsumerState<_CaseShareSheet> createState() => _CaseShareSheetState();
}

class _CaseShareSheetState extends ConsumerState<_CaseShareSheet> {
  String? _memberId;
  ShareAccess _access = ShareAccess.read;
  var _busy = false;

  Future<void> _grant(AppUser me) async {
    final memberId = _memberId;
    if (memberId == null || _busy) return;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    setState(() => _busy = true);
    try {
      final repo = await ref.read(caseSharesRepositoryProvider.future);
      await repo.create({
        'case': widget.caseId,
        'shared_with': memberId,
        'access': _access.wire,
        'shared_by': me.id,
        'org': ?me.org,
      });
      ref.invalidate(caseSharesProvider(widget.caseId));
      setState(() {
        _memberId = null;
        _access = ShareAccess.read;
      });
    } on Object catch (e, stackTrace) {
      reportCaughtError(e, stackTrace);
      messenger.showSnackBar(SnackBar(content: Text(errorMessage(l10n, e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setAccess(CaseShare share, ShareAccess access) async {
    if (_busy || access == share.access) return;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    setState(() => _busy = true);
    try {
      final repo = await ref.read(caseSharesRepositoryProvider.future);
      await repo.update(share.id, {'access': access.wire});
      ref.invalidate(caseSharesProvider(widget.caseId));
    } on Object catch (e, stackTrace) {
      reportCaughtError(e, stackTrace);
      messenger.showSnackBar(SnackBar(content: Text(errorMessage(l10n, e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revoke(CaseShare share, String memberName) async {
    if (_busy) return;
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.caseShareRevokeTitle),
        content: Text(l10n.caseShareRevokeConfirm(memberName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.actionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.caseShareRevokeAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _busy) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final repo = await ref.read(caseSharesRepositoryProvider.future);
      await repo.delete(share.id);
      ref.invalidate(caseSharesProvider(widget.caseId));
    } on Object catch (e, stackTrace) {
      reportCaughtError(e, stackTrace);
      messenger.showSnackBar(SnackBar(content: Text(errorMessage(l10n, e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// One existing share: who has it, at which level (changeable in place via
  /// the menu), and a revoke button guarded by a confirmation dialog.
  Widget _shareTile(
    AppLocalizations l10n,
    CaseShare share,
    Map<String, AppUser> byId,
  ) {
    final member = byId[share.sharedWith];
    final memberName = member != null ? memberLabel(member) : share.sharedWith;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.person_outline),
      title: Text(memberName),
      subtitle: Text(shareAccessLabel(l10n, share.access)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PopupMenuButton<ShareAccess>(
            icon: const Icon(Icons.edit_outlined),
            tooltip: l10n.caseShareChangeAccess,
            enabled: !_busy,
            onSelected: (access) => _setAccess(share, access),
            itemBuilder: (_) => [
              for (final access in ShareAccess.values)
                CheckedPopupMenuItem(
                  value: access,
                  checked: access == share.access,
                  child: Text(shareAccessLabel(l10n, access)),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: l10n.caseShareRevoke,
            onPressed: _busy ? null : () => _revoke(share, memberName),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final shares = ref.watch(caseSharesProvider(widget.caseId));
    final members = ref.watch(orgMembersProvider);
    final me = ref.watch(currentUserProvider).value;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.caseShareTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.md),
            if (shares.isLoading || members.isLoading || me == null)
              const Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              ..._content(
                l10n,
                theme,
                shares.value ?? const [],
                members.value ?? const [],
                me,
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _content(
    AppLocalizations l10n,
    ThemeData theme,
    List<CaseShare> shares,
    List<AppUser> members,
    AppUser me,
  ) {
    final byId = {for (final m in members) m.id: m};
    final sharedIds = shares.map((s) => s.sharedWith).toSet();
    final eligible = members
        .where(
          (m) =>
              m.id != me.id &&
              m.id != widget.activeCarer &&
              !sharedIds.contains(m.id),
        )
        .toList();

    return [
      if (shares.isEmpty)
        Text(
          l10n.caseShareNone,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        )
      else
        for (final share in shares) _shareTile(l10n, share, byId),
      const Divider(height: AppSpacing.lg),
      if (eligible.isEmpty)
        Text(
          l10n.caseShareNoMembers,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        )
      else ...[
        DropdownButtonFormField<String>(
          initialValue: _memberId,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: l10n.caseShareMemberLabel,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          items: [
            for (final m in eligible)
              DropdownMenuItem(value: m.id, child: Text(memberLabel(m))),
          ],
          onChanged: (id) => setState(() => _memberId = id),
        ),
        const SizedBox(height: AppSpacing.md),
        SegmentedButton<ShareAccess>(
          segments: [
            ButtonSegment(
              value: ShareAccess.read,
              label: Text(l10n.caseShareAccessRead),
            ),
            ButtonSegment(
              value: ShareAccess.edit,
              label: Text(l10n.caseShareAccessEdit),
            ),
          ],
          selected: {_access},
          onSelectionChanged: (s) => setState(() => _access = s.first),
        ),
        const SizedBox(height: AppSpacing.md),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: _memberId == null || _busy ? null : () => _grant(me),
            child: Text(l10n.caseShareAction),
          ),
        ),
      ],
      if (me.role == UserRole.carer) ...[
        const SizedBox(height: AppSpacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                l10n.caseShareRoleHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ],
    ];
  }
}
