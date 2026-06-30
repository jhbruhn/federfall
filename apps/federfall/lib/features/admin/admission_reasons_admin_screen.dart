import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/auth/roles.dart';
import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/admin/admission_reason_codelist_sheet.dart';
import 'package:federfall/features/cases/admission_reasons_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Supervisor-only admission-reason code-list editor: maintain the org's
/// reasons-for-admission vocabulary. Re-checks the role so a typed-in URL
/// degrades gracefully — the server rules remain the real boundary.
class AdmissionReasonsAdminScreen extends ConsumerWidget {
  const AdmissionReasonsAdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final role = ref.watch(currentUserProvider).value?.role;

    if (!canManageTeam(role)) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.admissionReasonsAdminTitle)),
        body: EmptyView(
          icon: Icons.lock_outline,
          message: l10n.errorUnauthorized,
        ),
      );
    }

    final reasons = ref.watch(admissionReasonsProvider);

    return Scaffold(
      appBar: AppBar(
        // No up arrow when shown as the right pane of the admin two-pane.
        automaticallyImplyLeading: !context.isExpanded,
        title: Text(l10n.admissionReasonsAdminTitle),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final changed = await showAdmissionReasonCodelistSheet(context);
          if (changed ?? false) ref.invalidate(admissionReasonsProvider);
        },
        icon: const Icon(Icons.add),
        label: Text(l10n.admissionReasonCodelistNewTitle),
      ),
      body: AsyncValueView<List<AdmissionReason>>(
        value: reasons,
        onRetry: () => ref.invalidate(admissionReasonsProvider),
        errorMessage: (e) => errorMessage(l10n, e),
        data: (list) => list.isEmpty
            ? EmptyView(
                icon: Icons.checklist_outlined,
                message: l10n.admissionReasonsAdminEmpty,
              )
            : ContentBounds(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 88),
                  children: [
                    for (final r in list) _AdmissionReasonTile(reason: r),
                  ],
                ),
              ),
      ),
    );
  }
}

class _AdmissionReasonTile extends ConsumerWidget {
  const _AdmissionReasonTile({required this.reason});

  final AdmissionReason reason;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.admissionReasonCodelistDeleteAction),
        content: Text(l10n.admissionReasonCodelistDeleteConfirm(reason.label)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.actionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.admissionReasonCodelistDeleteAction),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final repo = await ref.read(admissionReasonsRepositoryProvider.future);
    await repo.delete(reason.id);
    ref.invalidate(admissionReasonsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final inactive = !reason.active;

    return ListTile(
      leading: Icon(
        Icons.label_outline,
        color: inactive ? theme.colorScheme.outline : null,
      ),
      title: Text(
        reason.label,
        style: inactive
            ? TextStyle(color: theme.colorScheme.onSurfaceVariant)
            : null,
      ),
      subtitle: inactive ? Text(l10n.conditionInactiveBadge) : null,
      onTap: () async {
        final changed = await showAdmissionReasonCodelistSheet(
          context,
          reason: reason,
        );
        if (changed ?? false) ref.invalidate(admissionReasonsProvider);
      },
      trailing: PopupMenuButton<void>(
        icon: const Icon(Icons.more_vert),
        itemBuilder: (_) => [
          PopupMenuItem(
            onTap: () => _delete(context, ref),
            child: Text(l10n.admissionReasonCodelistDeleteAction),
          ),
        ],
      ),
    );
  }
}
