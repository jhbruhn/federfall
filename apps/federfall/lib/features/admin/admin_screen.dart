import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/auth/roles.dart';
import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/features/admin/admin_providers.dart';
import 'package:federfall/features/admin/invite_member_sheet.dart';
import 'package:federfall/features/admin/member_management_sheet.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/routing/app_routes.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Supervisor-only admin area (FED-3.3 / FED-3.2). Hosts the team roster and
/// the invite flow. Re-checks the role so a typed-in URL degrades gracefully —
/// the real boundary remains the server API rules.
class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final role = ref.watch(currentUserProvider).value?.role;

    if (!canManageTeam(role)) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.adminTitle)),
        body: EmptyView(
          icon: Icons.lock_outline,
          message: l10n.errorUnauthorized,
        ),
      );
    }

    final members = ref.watch(orgMembersProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.adminTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: l10n.orgSettingsTitle,
            onPressed: () => context.push(AppRoutes.orgSettings),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final invited = await showInviteMemberSheet(context);
          if (invited ?? false) ref.invalidate(orgMembersProvider);
        },
        icon: const Icon(Icons.person_add_alt_1),
        label: Text(l10n.inviteSectionTitle),
      ),
      body: AsyncValueView<List<AppUser>>(
        value: members,
        onRetry: () => ref.invalidate(orgMembersProvider),
        errorMessage: (e) => errorMessage(l10n, e),
        data: (list) => list.isEmpty
            ? EmptyView(
                icon: Icons.group_outlined,
                message: l10n.adminNoMembers,
              )
            : ListView(
                padding: const EdgeInsets.only(bottom: 88),
                children: [
                  for (final m in list)
                    _MemberTile(
                      member: m,
                      onTap: () async {
                        final changed =
                            await showMemberManagementSheet(context, m);
                        if (changed ?? false) {
                          ref.invalidate(orgMembersProvider);
                        }
                      },
                    ),
                ],
              ),
      ),
    );
  }
}

/// One member in the roster: name (or email), role, and a status badge for
/// inactive or not-yet-onboarded accounts. Management actions land in the
/// next task; the tile is informational for now.
class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.member, this.onTap});

  final AppUser member;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final name = member.name;
    final hasName = name != null && name.isNotEmpty;
    final role = member.role;

    final badge = _statusBadge(context);

    return ListTile(
      leading: CircleAvatar(
        child: Text(_initial(hasName ? name : member.email)),
      ),
      title: Text(hasName ? name : member.email),
      subtitle: Text(
        [
          if (hasName) member.email,
          if (role != null) userRoleLabel(l10n, role),
        ].join(' · '),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ?badge,
          if (onTap != null) const Icon(Icons.chevron_right),
        ],
      ),
      onTap: onTap,
    );
  }

  Widget? _statusBadge(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    if (!member.isActive) {
      return _Chip(
        label: l10n.memberInactive,
        color: theme.colorScheme.errorContainer,
        onColor: theme.colorScheme.onErrorContainer,
      );
    }
    if (!member.verified) {
      return _Chip(
        label: l10n.memberInvitePending,
        color: theme.colorScheme.tertiaryContainer,
        onColor: theme.colorScheme.onTertiaryContainer,
      );
    }
    return null;
  }

  String _initial(String s) =>
      s.trim().isEmpty ? '?' : s.trim().characters.first.toUpperCase();
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.color,
    required this.onColor,
  });

  final String label;
  final Color color;
  final Color onColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(color: onColor),
      ),
    );
  }
}
