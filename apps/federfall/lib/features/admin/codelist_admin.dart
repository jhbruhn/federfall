import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/auth/roles.dart';
import 'package:federfall/features/admin/codelist_delete.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A multi-select over a fixed vocabulary, rendered as a chip group in the
/// code-list sheet and as badges on the tile.
///
/// Values are the WIRE strings the column stores, not a Dart enum: this is the
/// boundary where the form becomes a request body, and keeping the enum out
/// means one list's control needs no new type parameter on [CodelistSpec].
class CodelistChips<T> {
  const CodelistChips({
    required this.field,
    required this.label,
    required this.help,
    required this.options,
    required this.optionLabel,
    required this.read,
  });

  /// The PocketBase column this writes (e.g. `sample_types`).
  final String field;

  final String Function(AppLocalizations) label;
  final String Function(AppLocalizations) help;

  /// The wire values on offer, in the order they should be shown.
  final List<String> options;

  final String Function(AppLocalizations, String wire) optionLabel;

  /// The wire values currently set on an entry.
  final List<String> Function(T) read;
}

/// Describes one supervisor-managed code list for the shared admin screen and
/// edit sheet: how to read, refresh and mutate its entries, plus the strings
/// and icons that differ per list. Every list is structurally a
/// `{label, active}` record; conditions additionally carry a description, a
/// notifiable flag and a contagious flag, enabled by providing
/// [description]/[notifiable]/[contagious], and a list needing a control none
/// of those cover supplies [chips].
///
/// The concrete specs live in `codelist_specs.dart`.
class CodelistSpec<T> {
  const CodelistSpec({
    required this.watchList,
    required this.refresh,
    required this.repository,
    required this.id,
    required this.label,
    required this.active,
    required this.tileIcon,
    required this.emptyIcon,
    required this.title,
    required this.emptyMessage,
    required this.newTitle,
    required this.editTitle,
    required this.deleteAction,
    required this.deleteConfirm,
    required this.activeHelp,
    required this.countReferences,
    required this.inUse,
    this.description,
    this.notifiable,
    this.contagious,
    this.chips,
    this.deleteBlockedWhenInUse = false,
  });

  /// Watches the list provider (the full code list, label-sorted).
  final AsyncValue<List<T>> Function(WidgetRef ref) watchList;

  /// Invalidates the list provider after a mutation.
  final void Function(WidgetRef ref) refresh;

  /// Resolves the repository the sheet/tile mutate entries through.
  final Future<Repository<T>> Function(WidgetRef ref) repository;

  final String Function(T) id;
  final String Function(T) label;
  final bool Function(T) active;

  final IconData tileIcon;
  final IconData emptyIcon;

  final String Function(AppLocalizations) title;
  final String Function(AppLocalizations) emptyMessage;
  final String Function(AppLocalizations) newTitle;
  final String Function(AppLocalizations) editTitle;
  final String Function(AppLocalizations) deleteAction;
  final String Function(AppLocalizations, String label) deleteConfirm;
  final String Function(AppLocalizations) activeHelp;

  /// Counts the live records that still point at an entry, summed across every
  /// collection referencing this list. Awaited before the delete confirmation
  /// so the dialog can name the number — see [confirmCodelistDelete].
  final Future<int> Function(WidgetRef ref, T entry) countReferences;

  /// Names what [countReferences] counted ("3 markings use this type").
  final String Function(AppLocalizations, int count) inUse;

  /// True when the referencing relation is **required**, so PocketBase refuses
  /// the delete outright while any reference exists. Only `markings.type` is:
  /// the other three lists are referenced by optional relations, where a
  /// delete succeeds and silently blanks the field on every referencing record.
  final bool deleteBlockedWhenInUse;

  /// Reads the optional free-text description; non-null adds the field to the
  /// sheet (stored as `description`).
  final String? Function(T)? description;

  /// Reads the optional notifiable flag; non-null adds the switch to the
  /// sheet (stored as `is_notifiable`) and the badge to the tile.
  final bool Function(T)? notifiable;

  /// Reads the optional contagious flag; non-null adds the switch to the
  /// sheet (stored as `is_contagious`) and the badge to the tile.
  final bool Function(T)? contagious;

  /// An extra multi-select this list needs beyond `{label, active}` — the
  /// microscopy vocabulary's `sample_types` applicability. Non-null adds the
  /// chip group to the sheet and the chosen labels to the tile subtitle.
  final CodelistChips<T>? chips;
}

/// Supervisor-only code-list editor (UX Phase A): maintain one of the org's
/// vocabularies, described by [spec]. Re-checks the role so a typed-in URL
/// degrades gracefully — the server rules remain the real boundary.
class CodelistAdminScreen<T> extends ConsumerWidget {
  const CodelistAdminScreen({required this.spec, super.key});

  final CodelistSpec<T> spec;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final role = ref.watch(currentUserProvider).value?.role;

    if (!canManageTeam(role)) {
      return Scaffold(
        appBar: AppBar(title: Text(spec.title(l10n))),
        body: EmptyView(
          icon: Icons.lock_outline,
          message: l10n.errorUnauthorized,
        ),
      );
    }

    final entries = spec.watchList(ref);

    return Scaffold(
      appBar: AppBar(
        // No up arrow when shown as the right pane of the admin two-pane.
        automaticallyImplyLeading: !context.isExpanded,
        title: Text(spec.title(l10n)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final changed = await showCodelistSheet(context, spec: spec);
          if (changed ?? false) spec.refresh(ref);
        },
        icon: const Icon(Icons.add),
        label: Text(spec.newTitle(l10n)),
      ),
      body: AsyncValueView<List<T>>(
        value: entries,
        onRetry: () => spec.refresh(ref),
        data: (list) => list.isEmpty
            ? EmptyView(
                icon: spec.emptyIcon,
                message: spec.emptyMessage(l10n),
              )
            : ContentBounds(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 88),
                  children: [
                    for (final e in list) _CodelistTile(spec: spec, entry: e),
                  ],
                ),
              ),
      ),
    );
  }
}

class _CodelistTile<T> extends ConsumerWidget {
  const _CodelistTile({required this.spec, required this.entry});

  final CodelistSpec<T> spec;
  final T entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final inactive = !spec.active(entry);
    final badges = [
      if (spec.notifiable?.call(entry) ?? false) l10n.conditionNotifiableLabel,
      if (spec.contagious?.call(entry) ?? false) l10n.conditionContagiousLabel,
      if (spec.chips case final chips?)
        for (final wire in chips.read(entry)) chips.optionLabel(l10n, wire),
      if (inactive) l10n.conditionInactiveBadge,
    ];

    return ListTile(
      leading: Icon(
        spec.tileIcon,
        color: inactive ? theme.colorScheme.outline : null,
      ),
      title: Text(
        spec.label(entry),
        style: inactive
            ? TextStyle(color: theme.colorScheme.onSurfaceVariant)
            : null,
      ),
      subtitle: badges.isEmpty ? null : Text(badges.join(' · ')),
      onTap: () async {
        final changed = await showCodelistSheet(
          context,
          spec: spec,
          entry: entry,
        );
        if (changed ?? false) spec.refresh(ref);
      },
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        tooltip: spec.deleteAction(l10n),
        onPressed: () =>
            confirmCodelistDelete(context, ref, spec: spec, entry: entry),
      ),
    );
  }
}

/// Create ([entry] null) or edit a code-list entry (supervisor only).
/// Resolves to `true` if the list changed so the caller can refresh.
Future<bool?> showCodelistSheet<T>(
  BuildContext context, {
  required CodelistSpec<T> spec,
  T? entry,
}) {
  return showAppSheet<bool>(
    context,
    builder: (_) => CodelistSheet<T>(spec: spec, entry: entry),
  );
}

class CodelistSheet<T> extends ConsumerStatefulWidget {
  const CodelistSheet({required this.spec, this.entry, super.key});

  final CodelistSpec<T> spec;
  final T? entry;

  @override
  ConsumerState<CodelistSheet<T>> createState() => _CodelistSheetState<T>();
}

class _CodelistSheetState<T> extends ConsumerState<CodelistSheet<T>>
    with DiscardGuard, FormSheetState {
  late final TextEditingController _label;
  TextEditingController? _description;
  late bool _notifiable;
  late bool _contagious;
  late bool _active;
  late final Set<String> _chips;

  CodelistSpec<T> get _spec => widget.spec;

  bool get _isEditing => widget.entry != null;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _label = TextEditingController(text: e == null ? '' : _spec.label(e));
    if (_spec.description case final read?) {
      _description = TextEditingController(
        text: e == null ? '' : read(e) ?? '',
      );
    }
    _notifiable = e != null && (_spec.notifiable?.call(e) ?? false);
    _contagious = e != null && (_spec.contagious?.call(e) ?? false);
    _active = e == null || _spec.active(e);
    // A new entry starts with every option ticked. An unticked chip group is
    // what a supervisor gets by not touching the control, and shipping that as
    // "applies nowhere" would hide the entry they just created.
    final chips = _spec.chips;
    _chips = switch (chips) {
      null => <String>{},
      _ when e == null => chips.options.toSet(),
      _ => chips.read(e as T).toSet(),
    };
  }

  @override
  void dispose() {
    _label.dispose();
    _description?.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(formKey.currentState?.validate() ?? false)) return;
    final navigator = Navigator.of(context);

    final ok = await runSave(() async {
      final repo = await _spec.repository(ref);
      final body = <String, dynamic>{
        'label': _label.text.trim(),
        'active': _active,
        if (_description case final d?) 'description': d.text.trim(),
        if (_spec.notifiable != null) 'is_notifiable': _notifiable,
        if (_spec.contagious != null) 'is_contagious': _contagious,
        // Sent in the vocabulary's own order, not selection order, so an edit
        // that changes nothing produces no diff for the audit log to record.
        if (_spec.chips case final chips?)
          chips.field: [
            for (final o in chips.options)
              if (_chips.contains(o)) o,
          ],
      };
      final existing = widget.entry;
      if (existing == null) {
        final me = await ref.read(currentUserProvider.future);
        await repo.create({...body, 'org': ?me?.org});
      } else {
        await repo.update(_spec.id(existing), body);
      }
      _spec.refresh(ref);
    });
    if (ok && mounted) navigator.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return guardUnsavedChanges(
      child: SheetScaffold(
        title: _isEditing ? _spec.editTitle(l10n) : _spec.newTitle(l10n),
        formKey: formKey,
        onFormChanged: markDirty,
        isBusy: isBusy,
        error: saveError,
        onSave: _save,
        children: [
          AppTextField(
            controller: _label,
            label: l10n.conditionLabelLabel,
            prefixIcon: Icons.label_outline,
            enabled: !isBusy,
            validator: Validators.required(l10n),
          ),
          if (_description case final description?) ...[
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              controller: description,
              label: l10n.conditionDescriptionLabel,
              enabled: !isBusy,
              minLines: 2,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
            ),
          ],
          if (_spec.chips case final chips?) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              chips.label(l10n),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (final option in chips.options)
                  FilterChip(
                    label: Text(chips.optionLabel(l10n, option)),
                    selected: _chips.contains(option),
                    onSelected: isBusy
                        ? null
                        : (on) {
                            setState(() {
                              if (on) {
                                _chips.add(option);
                              } else {
                                _chips.remove(option);
                              }
                            });
                            markDirty();
                          },
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                chips.help(l10n),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          if (_spec.notifiable != null)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.conditionNotifiableLabel),
              subtitle: Text(l10n.conditionNotifiableHelp),
              value: _notifiable,
              onChanged: isBusy
                  ? null
                  : (v) {
                      setState(() => _notifiable = v);
                      markDirty();
                    },
            ),
          if (_spec.contagious != null)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.conditionContagiousLabel),
              subtitle: Text(l10n.conditionContagiousHelp),
              value: _contagious,
              onChanged: isBusy
                  ? null
                  : (v) {
                      setState(() => _contagious = v);
                      markDirty();
                    },
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.conditionActiveLabel),
            subtitle: Text(_spec.activeHelp(l10n)),
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
}
