import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/auth/roles.dart';
import 'package:federfall/core/error/quick_action.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/cases_labels.dart';
import 'package:federfall/features/cases/medications/medication_products_providers.dart';
import 'package:federfall/features/cases/medications/medication_routes_providers.dart';
import 'package:federfall/features/cases/medications/medications_providers.dart';
import 'package:federfall/features/cases/medications/prescription_sheet.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The org's drug catalogue (federfall-6d3a.3), maintained by a supervisor.
///
/// Not a `CodelistSpec` like the other four vocabularies: those are all
/// `{label, active}` records, while an entry here carries a unit, a rate, an
/// advisory range, a strength, a route and a schedule — six typed fields that
/// the shared sheet has no shape for. Generalising it would cost more than the
/// screen it saves.
class MedicationProductsScreen extends ConsumerWidget {
  const MedicationProductsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final role = ref.watch(currentUserProvider).value?.role;

    // Re-checked so a typed-in URL degrades gracefully; the server rules stay
    // the real boundary.
    if (!canManageTeam(role)) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.medProductsAdminTitle)),
        body: EmptyView(
          icon: Icons.lock_outline,
          message: l10n.errorUnauthorized,
        ),
      );
    }

    final products = ref.watch(medicationProductsProvider);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !context.isExpanded,
        title: Text(l10n.medProductsAdminTitle),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final changed = await showMedicationProductSheet(context);
          if (changed ?? false) ref.invalidate(medicationProductsProvider);
        },
        icon: const Icon(Icons.add),
        label: Text(l10n.medProductNewTitle),
      ),
      body: AsyncValueView<List<MedicationProduct>>(
        value: products,
        onRetry: () => ref.invalidate(medicationProductsProvider),
        data: (list) => list.isEmpty
            ? EmptyView(
                icon: Icons.inventory_2_outlined,
                message: l10n.medProductsAdminEmpty,
              )
            : ContentBounds(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 88),
                  children: [
                    for (final p in list) _ProductTile(product: p),
                  ],
                ),
              ),
      ),
    );
  }
}

class _ProductTile extends ConsumerWidget {
  const _ProductTile({required this.product});

  final MedicationProduct product;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.medProductDeleteTitle),
        content: Text(l10n.medProductDeleteConfirm(product.label)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.actionCancel),
          ),
          DestructiveActionButton(
            label: l10n.medDeleteAction,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await runQuickAction(context, () async {
      final repo = await ref.read(medicationProductsRepositoryProvider.future);
      await repo.delete(product.id);
      ref.invalidate(medicationProductsProvider);
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final routesById =
        ref.watch(medicationRoutesByIdProvider).value ?? const {};
    final unit = product.doseUnit ?? '';
    final frequency = medicationFrequencyLabel(
      l10n,
      product.frequencyKind,
      product.intervalHours,
    );
    final detail = [
      if (product.doseRate case final r?)
        formatDose(l10n, r, unit.isEmpty ? null : '$unit/kg'),
      if (product.concentrationPerMl case final c?)
        formatDose(l10n, c, unit.isEmpty ? null : '$unit/ml'),
      ?routesById[product.route]?.label,
      if (frequency.isNotEmpty) frequency,
      if (!product.active) l10n.conditionInactiveBadge,
    ].join(' · ');

    return ListTile(
      leading: Icon(
        Icons.inventory_2_outlined,
        color: product.active ? null : theme.colorScheme.outline,
      ),
      title: Text(
        product.label,
        style: product.active
            ? null
            : TextStyle(color: theme.colorScheme.onSurfaceVariant),
      ),
      subtitle: detail.isEmpty ? null : Text(detail),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        tooltip: l10n.medDeleteAction,
        onPressed: () => _delete(context, ref),
      ),
      onTap: () async {
        final changed = await showMedicationProductSheet(
          context,
          product: product,
        );
        if (changed ?? false) ref.invalidate(medicationProductsProvider);
      },
    );
  }
}

/// Opens the catalogue entry add/edit form.
Future<bool?> showMedicationProductSheet(
  BuildContext context, {
  MedicationProduct? product,
}) {
  return showAppSheet<bool>(
    context,
    builder: (_) => MedicationProductSheet(product: product),
  );
}

/// Add/edit form for one catalogue entry. Mirrors the prescription form's own
/// grouping and units, since that is where these values end up.
class MedicationProductSheet extends ConsumerStatefulWidget {
  const MedicationProductSheet({this.product, super.key});

  final MedicationProduct? product;

  @override
  ConsumerState<MedicationProductSheet> createState() =>
      _MedicationProductSheetState();
}

class _MedicationProductSheetState extends ConsumerState<MedicationProductSheet>
    with DiscardGuard, FormSheetState {
  late final TextEditingController _label;
  late final TextEditingController _unit;
  late final TextEditingController _rate;
  late final TextEditingController _min;
  late final TextEditingController _max;
  late final TextEditingController _concentration;
  late final TextEditingController _note;
  String? _route;
  MedicationFrequencyKind? _frequencyKind;
  late final TextEditingController _intervalHours;
  bool _active = true;
  bool _seeded = false;

  bool get _isEditing => widget.product != null;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _label = TextEditingController(text: p?.label ?? '');
    _unit = TextEditingController(text: p?.doseUnit ?? 'mg');
    _rate = TextEditingController();
    _min = TextEditingController();
    _max = TextEditingController();
    _concentration = TextEditingController();
    _note = TextEditingController(text: p?.note ?? '');
    _intervalHours = TextEditingController(
      text: p?.intervalHours == null ? '' : '${p!.intervalHours}',
    );
    _route = p?.route;
    _frequencyKind = p?.frequencyKind;
    _active = p?.active ?? true;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Numbers are written with the locale's separator, which needs
    // Localizations — unavailable in initState.
    if (_seeded) return;
    _seeded = true;
    final l10n = context.l10n;
    final p = widget.product;
    if (p == null) return;
    if (p.doseRate != null) _rate.text = formatDose(l10n, p.doseRate, null);
    if (p.rateMin != null) _min.text = formatDose(l10n, p.rateMin, null);
    if (p.rateMax != null) _max.text = formatDose(l10n, p.rateMax, null);
    if (p.concentrationPerMl != null) {
      _concentration.text = formatDose(l10n, p.concentrationPerMl, null);
    }
  }

  @override
  void dispose() {
    for (final c in [
      _label,
      _unit,
      _rate,
      _min,
      _max,
      _concentration,
      _note,
      _intervalHours,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  double? _number(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '.'));

  Future<void> _save() async {
    if (!(formKey.currentState?.validate() ?? false)) return;

    final ok = await runSave(() async {
      final (_, org) = await requireUserOrg();
      final repo = await ref.read(medicationProductsRepositoryProvider.future);
      final body = <String, dynamic>{
        'label': _label.text.trim(),
        'dose_unit': trimToNull(_unit) ?? '',
        'dose_rate': _number(_rate),
        'rate_min': _number(_min),
        'rate_max': _number(_max),
        'concentration_per_ml': _number(_concentration),
        'route': _route ?? '',
        'frequency_kind': _frequencyKind?.wire ?? '',
        'interval_hours': int.tryParse(_intervalHours.text.trim()),
        'note': trimToNull(_note) ?? '',
        'active': _active,
      };

      final product = widget.product;
      if (product == null) {
        await repo.create({...body, 'org': org});
      } else {
        await repo.update(product.id, body);
      }
      ref.invalidate(medicationProductsProvider);
    });
    if (ok && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final unit = _unit.text.trim();

    return guardUnsavedChanges(
      child: SheetScaffold(
        title: _isEditing ? l10n.medProductEditTitle : l10n.medProductNewTitle,
        formKey: formKey,
        onFormChanged: markDirty,
        isBusy: isBusy,
        error: saveError,
        onSave: _save,
        children: [
          AppTextField(
            controller: _label,
            label: l10n.medDrug,
            prefixIcon: Icons.medication_outlined,
            enabled: !isBusy,
            validator: Validators.required(l10n),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: _Number(
                  controller: _rate,
                  label: l10n.doseCalcRate,
                  suffix: unit.isEmpty ? null : '$unit/kg',
                  enabled: !isBusy,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                flex: 2,
                child: AppTextField(
                  controller: _unit,
                  label: l10n.medUnit,
                  enabled: !isBusy,
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          // The advisory range: what the prescription form warns outside of.
          Row(
            children: [
              Expanded(
                child: _Number(
                  controller: _min,
                  label: l10n.medRateMin,
                  suffix: unit.isEmpty ? null : '$unit/kg',
                  enabled: !isBusy,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _Number(
                  controller: _max,
                  label: l10n.medRateMax,
                  suffix: unit.isEmpty ? null : '$unit/kg',
                  enabled: !isBusy,
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _Number(
            controller: _concentration,
            label: l10n.doseCalcConcentration,
            suffix: unit.isEmpty ? null : '$unit/ml',
            enabled: !isBusy,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.md),
          MedicationRouteDropdown(
            value: _route,
            enabled: !isBusy,
            onChanged: (r) => setState(() => _route = r),
          ),
          const SizedBox(height: AppSpacing.md),
          DropdownButtonFormField<MedicationFrequencyKind?>(
            initialValue: _frequencyKind,
            decoration: InputDecoration(
              labelText: l10n.medFrequency,
              prefixIcon: const Icon(Icons.repeat),
            ),
            items: [
              DropdownMenuItem(child: Text(l10n.medProductNoDefault)),
              for (final k in MedicationFrequencyKind.values)
                DropdownMenuItem(value: k, child: Text(_kindLabel(l10n, k))),
            ],
            onChanged: isBusy
                ? null
                : (k) => setState(() => _frequencyKind = k),
          ),
          if (_frequencyKind == MedicationFrequencyKind.scheduled) ...[
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              controller: _intervalHours,
              label: l10n.medIntervalHours,
              prefixIcon: Icons.timelapse_outlined,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              enabled: !isBusy,
              validator: (v) {
                final n = int.tryParse((v ?? '').trim());
                return (n == null || n <= 0) ? l10n.fieldRequired : null;
              },
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: _note,
            label: l10n.medNotes,
            enabled: !isBusy,
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.medProductActive),
            subtitle: Text(l10n.medProductActiveHelp),
            value: _active,
            onChanged: isBusy
                ? null
                : (v) {
                    setState(() => _active = v);
                    markDirty();
                  },
          ),
        ],
      ),
    );
  }

  String _kindLabel(AppLocalizations l10n, MedicationFrequencyKind kind) =>
      switch (kind) {
        MedicationFrequencyKind.once => l10n.freqOnce,
        MedicationFrequencyKind.scheduled => l10n.freqCustom,
        MedicationFrequencyKind.asNeeded => l10n.freqAsNeeded,
      };
}

/// A decimal input that also accepts the comma every German keyboard offers.
class _Number extends StatelessWidget {
  const _Number({
    required this.controller,
    required this.label,
    required this.enabled,
    required this.onChanged,
    this.suffix,
  });

  final TextEditingController controller;
  final String label;
  final String? suffix;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      controller: controller,
      label: label,
      suffixText: suffix,
      enabled: enabled,
      onChanged: onChanged,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[0-9.,]'))],
    );
  }
}
