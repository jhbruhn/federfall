import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/features/cases/cases_labels.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Read-only case detail (FED-3.4 stub). The full overview — clinical logs,
/// weights, dispositions — arrives in FED-4.3 / Phase 4.
class CaseDetailScreen extends ConsumerWidget {
  const CaseDetailScreen({required this.caseId, super.key});

  final String caseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final caseAsync = ref.watch(caseByIdProvider(caseId));

    return Scaffold(
      appBar: AppBar(title: Text(l10n.caseDetailTitle)),
      body: AsyncValueView<Case>(
        value: caseAsync,
        onRetry: () => ref.invalidate(caseByIdProvider(caseId)),
        errorMessage: (e) => errorMessage(l10n, e),
        data: _CaseDetail.new,
      ),
    );
  }
}

class _CaseDetail extends ConsumerWidget {
  const _CaseDetail(this.medicalCase);

  final Case medicalCase;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final animal = ref.watch(animalByIdProvider(medicalCase.animal)).value;

    final reasons = medicalCase.reasonsForAdmission
        .map((r) => admissionReasonLabel(l10n, r))
        .join(', ');
    final status = medicalCase.status;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.sm),
      children: [
        ListTile(
          leading: const Icon(Icons.tag),
          title: Text(l10n.caseNumberLabel),
          subtitle: Text(medicalCase.caseNumber ?? '—'),
        ),
        ListTile(
          leading: const Icon(Icons.pets_outlined),
          title: Text(l10n.caseAnimalLabel),
          subtitle: Text(_animalLine(animal)),
        ),
        ListTile(
          leading: const Icon(Icons.flag_outlined),
          title: Text(l10n.caseStatusFieldLabel),
          subtitle: Text(status == null ? '—' : caseStatusLabel(l10n, status)),
        ),
        ListTile(
          leading: const Icon(Icons.report_outlined),
          title: Text(l10n.caseReasonsFieldLabel),
          subtitle: Text(reasons.isEmpty ? '—' : reasons),
        ),
      ],
    );
  }

  String _animalLine(Animal? animal) {
    if (animal == null) return '—';
    final name = animal.name;
    return name == null || name.isEmpty
        ? animal.species
        : '${animal.species} · $name';
  }
}
