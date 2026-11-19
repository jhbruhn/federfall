import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/areas/care_areas_providers.dart';
import 'package:federfall/features/cases/areas/care_areas_sheet.dart';
import 'package:federfall/features/cases/cases_browser.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/features/cases/placements/placements_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// A muted "🚪 Garage" line naming the room the case's bird is in
/// (federfall-r67n), drawn under the carer in the case header.
///
/// Tappable for whoever may edit the case, and then it also shows when no
/// area is set yet — as the prompt to set one. A read-only viewer sees it only
/// when there is something to read. A closed case has no area (the server
/// empties it), so it renders nothing at all.
class CaseAreaLine extends ConsumerWidget {
  const CaseAreaLine({
    required this.medicalCase,
    required this.editable,
    super.key,
  });

  final Case medicalCase;
  final bool editable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (medicalCase.status == CaseStatus.disposed) {
      return const SizedBox.shrink();
    }
    final l10n = context.l10n;
    final areaId = medicalCase.area;
    final area = areaId == null
        ? null
        : ref.watch(careAreasByIdProvider).value?[areaId];
    if (area == null && !editable) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final line = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.meeting_room_outlined, size: 16, color: muted),
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text(
            area?.name ?? l10n.caseAreaAssign,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: area == null ? theme.colorScheme.primary : muted,
            ),
          ),
        ),
      ],
    );
    if (!editable) {
      return Tooltip(message: l10n.caseAreaLabel, child: line);
    }
    return Tooltip(
      message: l10n.caseAreaLabel,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: () => showCaseAreaPicker(context, medicalCase: medicalCase),
        child: line,
      ),
    );
  }
}

/// Lets the user say which of the active carer's areas the bird is in.
///
/// Only that carer's areas are offered — the server refuses any other — so a
/// supervisor or edit-share holder picks among the carer's rooms and is told
/// whose they are. Only the carer themself can add a room here, since an area
/// is always created as the caller's own.
Future<void> showCaseAreaPicker(
  BuildContext context, {
  required Case medicalCase,
}) => showAppSheet<void>(
  context,
  builder: (_) => _CaseAreaPicker(medicalCase: medicalCase),
);

class _CaseAreaPicker extends ConsumerStatefulWidget {
  const _CaseAreaPicker({required this.medicalCase});

  final Case medicalCase;

  @override
  ConsumerState<_CaseAreaPicker> createState() => _CaseAreaPickerState();
}

class _CaseAreaPickerState extends ConsumerState<_CaseAreaPicker> {
  bool _busy = false;

  Future<void> _assign(String areaId) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    try {
      final repo = await ref.read(casesRepositoryProvider.future);
      await repo.update(widget.medicalCase.id, {'area': areaId});
      ref
        ..invalidate(caseBundleProvider(widget.medicalCase.id))
        ..invalidate(caseBrowseFeedProvider);
      navigator.pop();
    } on Object catch (e, stackTrace) {
      reportCaughtError(e, stackTrace);
      messenger.showSnackBar(SnackBar(content: Text(errorMessage(l10n, e))));
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createAndAssign() async {
    final name = await askCareAreaName(context);
    if (name == null || !mounted) return;
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final area = await createCareArea(ref, name);
      await _assign(area.id);
    } on Object catch (e, stackTrace) {
      reportCaughtError(e, stackTrace);
      messenger.showSnackBar(SnackBar(content: Text(errorMessage(l10n, e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final carer = widget.medicalCase.activeCarer ?? '';
    final me = ref.watch(currentUserProvider).value?.id;
    final isMine = me != null && me == carer;
    final all = ref.watch(careAreasProvider).value ?? const <CareArea>[];
    final areas = areasOwnedBy(all, carer);
    final current = widget.medicalCase.area ?? '';
    final carerUser = isMine
        ? null
        : ref.watch(orgMembersByIdProvider).value?[carer];

    Widget option(String id, String label, {IconData? icon}) => ListTile(
      enabled: !_busy,
      leading: Icon(icon ?? Icons.meeting_room_outlined),
      title: Text(label),
      trailing: id == current ? const Icon(Icons.check) : null,
      selected: id == current,
      onTap: id == current
          ? () => Navigator.of(context).pop()
          : () => _assign(id),
    );

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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.caseAreaPickerTitle, style: theme.textTheme.titleLarge),
            if (carerUser != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                l10n.caseAreaPickerOtherCarer(memberLabel(carerUser)),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final a in areas) option(a.id, a.name),
                  option('', l10n.caseAreaNone, icon: Icons.block),
                  if (isMine)
                    ListTile(
                      enabled: !_busy,
                      leading: const Icon(Icons.add),
                      title: Text(l10n.careAreaAdd),
                      onTap: _createAndAssign,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
