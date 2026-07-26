import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/cases_browser.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/features/cases/placements/placements_providers.dart';
import 'package:federfall/features/dashboard/dashboard_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the placement form. Pass [placement] to edit an existing record
/// (editing never re-triggers a handoff). Resolves to `true` on save.
Future<bool?> showPlacementSheet(
  BuildContext context, {
  required Case medicalCase,
  Placement? placement,
}) {
  return showAppSheet<bool>(
    context,
    builder: (_) =>
        PlacementSheet(medicalCase: medicalCase, placement: placement),
  );
}

/// Records a placement (FED-4.9): where the bird is held and who holds it.
///
/// Choosing a carer other than the case's current active carer is a handoff:
/// the record carries `to_user`, and the backend hook updates the case's
/// `active_carer` from it in the same transaction (leaving the previous carer a
/// read share). There is deliberately no mode — this form used to come in a
/// "move" and a "handoff" flavour that differed only by whether the carer field
/// rendered, which asked the user to declare the distinction before seeing the
/// field that makes it (federfall-0se6). The field is always there; picking
/// someone else is the handoff, and the hint and confirmation say so the moment
/// it becomes one.
class PlacementSheet extends ConsumerStatefulWidget {
  const PlacementSheet({
    required this.medicalCase,
    this.placement,
    super.key,
  });

  final Case medicalCase;
  final Placement? placement;

  @override
  ConsumerState<PlacementSheet> createState() => _PlacementSheetState();
}

class _PlacementSheetState extends ConsumerState<PlacementSheet>
    with DiscardGuard, FormSheetState {
  late final TextEditingController _where;
  late final TextEditingController _area;
  late final TextEditingController _enclosure;
  late final TextEditingController _condition;
  late final TextEditingController _comments;
  String? _carerId;
  late DateTime _movedInAt;

  bool get _isEditing => widget.placement != null;

  /// Whether this save hands the case off: creating, with a carer other than
  /// the case's current active carer. The field starts on the current carer, so
  /// a placement is a plain move until the user changes it.
  bool get _isHandoff =>
      !_isEditing &&
      _carerId != null &&
      _carerId != widget.medicalCase.activeCarer;

  @override
  void initState() {
    super.initState();
    final p = widget.placement;
    _where = TextEditingController(text: p?.whereHolding ?? '');
    _area = TextEditingController(text: p?.area ?? '');
    _enclosure = TextEditingController(text: p?.enclosure ?? '');
    _condition = TextEditingController(text: p?.conditionAtHandoff ?? '');
    _comments = TextEditingController(text: p?.comments ?? '');
    _carerId = p?.carer ?? widget.medicalCase.activeCarer;
    _movedInAt = (p?.movedInAt ?? p?.created)?.toLocal() ?? DateTime.now();
  }

  @override
  void dispose() {
    for (final c in [_where, _area, _enclosure, _condition, _comments]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await pickDate(context, initial: _movedInAt);
    if (picked != null) {
      setState(() => _movedInAt = picked);
      markDirty();
    }
  }

  /// Asks the giver to confirm the handoff: they drop to a read share, which
  /// is too consequential for a hint text alone (federfall-h5m).
  Future<bool> _confirmHandoff() async {
    final l10n = context.l10n;
    final members = ref.read(orgMembersProvider).value ?? const <AppUser>[];
    final target = members.where((m) => m.id == _carerId).firstOrNull;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.placementHandoffConfirmTitle),
        content: Text(
          l10n.placementHandoffConfirmBody(
            target == null ? '?' : memberLabel(target),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.placementHandoffConfirmAction),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _save() async {
    if (!(formKey.currentState?.validate() ?? false)) return;
    // No "pick a different carer" error any more: keeping the current carer is
    // a legitimate move, and only the old handoff mode made it a mistake.
    final handoff = _isHandoff;
    if (handoff && !await _confirmHandoff()) return;

    final ok = await runSave(() async {
      final (_, org) = await requireUserOrg();
      final caseId = widget.medicalCase.id;
      final placementsRepo = await ref.read(
        placementsRepositoryProvider.future,
      );

      final body = <String, dynamic>{
        'moved_in_at': _movedInAt.toUtc().toIso8601String(),
        'carer': ?_carerId,
        'where_holding': trimToNull(_where) ?? '',
        'area': trimToNull(_area) ?? '',
        'enclosure': trimToNull(_enclosure) ?? '',
        'condition_at_handoff': trimToNull(_condition) ?? '',
        'comments': trimToNull(_comments) ?? '',
      };

      final placement = widget.placement;
      if (placement == null) {
        // A `to_user` makes this a handoff: the backend hook updates the
        // case's active_carer in the SAME transaction (and auto-shares the
        // previous carer read access), so the chain-of-custody record and the
        // carer change cannot diverge (federfall-h5m).
        await placementsRepo.create({
          ...body,
          'case': caseId,
          'from_user': ?widget.medicalCase.activeCarer,
          'to_user': handoff ? _carerId : null,
          'org': org,
        });
      } else {
        await placementsRepo.update(placement.id, body);
      }

      if (handoff) {
        ref
          ..invalidate(casesBrowserDataProvider)
          ..invalidate(dashboardSummaryProvider);
      }

      ref.invalidate(caseBundleProvider(caseId));
    });
    if (ok && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final members = ref.watch(orgMembersProvider).value ?? const <AppUser>[];

    return guardUnsavedChanges(
      child: SheetScaffold(
        title: _isEditing ? l10n.placementEditTitle : l10n.placementTitle,
        formKey: formKey,
        onFormChanged: markDirty,
        isBusy: isBusy,
        error: saveError,
        onSave: _save,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _carerId,
            decoration: InputDecoration(
              labelText: l10n.placementFieldCarer,
              prefixIcon: const Icon(Icons.person_outline),
            ),
            items: [
              for (final m in members)
                DropdownMenuItem(value: m.id, child: Text(memberLabel(m))),
            ],
            onChanged: isBusy ? null : (id) => setState(() => _carerId = id),
          ),
          // Appears the moment the picked carer differs from the current one:
          // the form says what the entry has just become, rather than the user
          // having had to declare it up front.
          if (_isHandoff) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.placementHandoffHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          DateField(
            label: l10n.placementFieldMovedAt,
            value: _movedInAt,
            enabled: !isBusy,
            onPick: _pickDate,
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _where,
            label: l10n.placementFieldWhere,
            prefixIcon: Icons.home_outlined,
            enabled: !isBusy,
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _enclosure,
            label: l10n.placementFieldEnclosure,
            prefixIcon: Icons.crop_square,
            enabled: !isBusy,
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _area,
            label: l10n.placementFieldArea,
            prefixIcon: Icons.map_outlined,
            enabled: !isBusy,
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _condition,
            label: l10n.placementFieldCondition,
            prefixIcon: Icons.health_and_safety_outlined,
            enabled: !isBusy,
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _comments,
            label: l10n.placementFieldComments,
            enabled: !isBusy,
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
          ),
        ],
      ),
    );
  }
}
