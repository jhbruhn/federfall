import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/auth/roles.dart';
import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/features/cases/cases_labels.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/routing/app_routes.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Authenticated landing: the carer's own cases with a create action, plus a
/// role-gated navigation bar (FED-3.3 / FED-3.4). The dashboard arrives in
/// Phase 7.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final cases = ref.watch(myCasesProvider);
    final role = ref.watch(currentUserProvider).value?.role;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.casesTitle),
        actions: [
          // Supervisor-only: team/admin area (FED-3.2 lands here).
          if (canManageTeam(role))
            IconButton(
              icon: const Icon(Icons.manage_accounts_outlined),
              tooltip: l10n.adminTitle,
              onPressed: () => context.push(AppRoutes.admin),
            ),
          IconButton(
            icon: const Icon(Icons.account_circle_outlined),
            tooltip: l10n.profileTitle,
            onPressed: () => context.push(AppRoutes.profile),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push(AppRoutes.newCase),
        tooltip: l10n.caseNewTitle,
        child: const Icon(Icons.add),
      ),
      body: AsyncValueView<List<Case>>(
        value: cases,
        onRetry: () => ref.invalidate(myCasesProvider),
        errorMessage: (e) => errorMessage(l10n, e),
        data: (list) => list.isEmpty
            ? EmptyView(message: l10n.casesEmpty)
            : ListView.builder(
                itemCount: list.length,
                itemBuilder: (context, i) => _CaseTile(list[i]),
              ),
      ),
    );
  }
}

class _CaseTile extends StatelessWidget {
  const _CaseTile(this.medicalCase);

  final Case medicalCase;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final status = medicalCase.status;
    final reasons = medicalCase.reasonsForAdmission
        .map((r) => admissionReasonLabel(l10n, r))
        .join(', ');

    return ListTile(
      leading: const Icon(Icons.medical_information_outlined),
      title: Text(medicalCase.caseNumber ?? l10n.caseNewTitle),
      subtitle: Text([
        if (status != null) caseStatusLabel(l10n, status),
        if (reasons.isNotEmpty) reasons,
      ].join(' · ')),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push(AppRoutes.caseDetail(medicalCase.id)),
    );
  }
}
