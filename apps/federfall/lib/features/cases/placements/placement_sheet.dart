import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/features/cases/placements/placements_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the placement / handoff form. Pass [placement] to edit an existing
/// move (editing never re-triggers a handoff). Resolves to `true` on save.
Future<bool?> showPlacementSheet(
  BuildContext context, {
  required Case medicalCase,
  Placement? placement,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => PlacementSheet(
      medicalCase: medicalCase,
      placement: placement,
    ),
  );
}

/// Records a placement / handoff (FED-4.9): where the bird is held and who
/// holds it. Choosing a carer other than the case's current active carer is a
/// handoff — it updates `active_carer` (the backend then leaves the previous
/// carer a read share) and records the from→to transfer.
class PlacementSheet extends ConsumerStatefulWidget {
  const PlacementSheet({required this.medicalCase, this.placement, super.key});

  final Case medicalCase;
  final Placement? placement;

  @override
  ConsumerState<PlacementSheet> createState() => _PlacementSheetState();
}

class _PlacementSheetState extends ConsumerState<PlacementSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _where;
  late final TextEditingController _area;
  late final TextEditingController _enclosure;
  late final TextEditingController _condition;
  late final TextEditingController _comments;
  String? _carerId;
  late DateTime _movedInAt;
  bool _busy = false;
  String? _error;

  bool get _isEditing => widget.placement != null;

  /// Whether the chosen carer differs from the case's current active carer
  /// (and we're creating) — i.e. this save hands the case off.
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
    _movedInAt = p?.movedInAt ?? p?.created ?? DateTime.now();
  }

  @override
  void dispose() {
    for (final c in [_where, _area, _enclosure, _condition, _comments]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _trim(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _movedInAt,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _movedInAt = picked);
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final user = await ref.read(currentUserProvider.future);
      final org = user?.org;
      if (user == null || org == null) {
        throw const RepositoryException('no org for current user');
      }
      final caseId = widget.medicalCase.id;
      final placementsRepo =
          await ref.read(placementsRepositoryProvider.future);
      final handoff = _isHandoff;

      final body = <String, dynamic>{
        'moved_in_at': _movedInAt.toUtc().toIso8601String(),
        'carer': ?_carerId,
        'where_holding': _trim(_where) ?? '',
        'area': _trim(_area) ?? '',
        'enclosure': _trim(_enclosure) ?? '',
        'condition_at_handoff': _trim(_condition) ?? '',
        'comments': _trim(_comments) ?? '',
      };

      final placement = widget.placement;
      if (placement == null) {
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

      // A handoff changes the active carer; the backend auto-shares the
      // previous carer (read) on this update.
      if (handoff) {
        final casesRepo = await ref.read(casesRepositoryProvider.future);
        await casesRepo.update(caseId, {'active_carer': _carerId});
        ref
          ..invalidate(caseByIdProvider(caseId))
          ..invalidate(myCasesProvider);
      }

      ref.invalidate(placementsForCaseProvider(caseId));
      if (mounted) Navigator.of(context).pop(true);
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
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    final members = ref.watch(orgMembersProvider).value ?? const <AppUser>[];

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg + viewInsets,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _isEditing
                    ? l10n.placementEditTitle
                    : l10n.placementNewTitle,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.md),
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
                onChanged: _busy
                    ? null
                    : (id) => setState(() => _carerId = id),
              ),
              if (_isHandoff) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  l10n.placementHandoffHint,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.primary),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              DateField(
                label: l10n.placementFieldMovedAt,
                value: _movedInAt,
                enabled: !_busy,
                onPick: _pickDate,
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                controller: _where,
                label: l10n.placementFieldWhere,
                prefixIcon: Icons.home_outlined,
                enabled: !_busy,
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                controller: _enclosure,
                label: l10n.placementFieldEnclosure,
                prefixIcon: Icons.crop_square,
                enabled: !_busy,
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                controller: _area,
                label: l10n.placementFieldArea,
                prefixIcon: Icons.map_outlined,
                enabled: !_busy,
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                controller: _condition,
                label: l10n.placementFieldCondition,
                prefixIcon: Icons.health_and_safety_outlined,
                enabled: !_busy,
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                controller: _comments,
                label: l10n.placementFieldComments,
                prefixIcon: Icons.notes_outlined,
                enabled: !_busy,
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _error!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
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
