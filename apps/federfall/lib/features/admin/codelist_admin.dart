import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/auth/roles.dart';
import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/core/error/quick_action.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Describes one supervisor-managed code list for the shared admin screen and
/// edit sheet: how to read, refresh and mutate its entries, plus the strings
/// and icons that differ per list. All four lists are structurally a
/// `{label, active}` record; conditions additionally carry a description and
/// a notifiable flag, enabled by providing [description]/[notifiable].
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
    this.description,
    this.notifiable,
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

  /// Reads the optional free-text description; non-null adds the field to the
  /// sheet (stored as `description`).
  final String? Function(T)? description;

  /// Reads the optional notifiable flag; non-null adds the switch to the
  /// sheet (stored as `is_notifiable`) and the badge to the tile.
  final bool Function(T)? notifiable;
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

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(spec.deleteAction(l10n)),
        content: Text(spec.deleteConfirm(l10n, spec.label(entry))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.actionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(spec.deleteAction(l10n)),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await runQuickAction(context, () async {
      final repo = await spec.repository(ref);
      await repo.delete(spec.id(entry));
      spec.refresh(ref);
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final inactive = !spec.active(entry);
    final badges = [
      if (spec.notifiable?.call(entry) ?? false) l10n.conditionNotifiableLabel,
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
      trailing: PopupMenuButton<void>(
        icon: const Icon(Icons.more_vert),
        itemBuilder: (_) => [
          PopupMenuItem(
            onTap: () => _delete(context, ref),
            child: Text(spec.deleteAction(l10n)),
          ),
        ],
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
    with DiscardGuard {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _label;
  TextEditingController? _description;
  late bool _notifiable;
  late bool _active;
  bool _busy = false;
  String? _error;

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
    _active = e == null || _spec.active(e);
  }

  @override
  void dispose() {
    _label.dispose();
    _description?.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final navigator = Navigator.of(context);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = await _spec.repository(ref);
      final body = <String, dynamic>{
        'label': _label.text.trim(),
        'active': _active,
        if (_description case final d?) 'description': d.text.trim(),
        if (_spec.notifiable != null) 'is_notifiable': _notifiable,
      };
      final existing = widget.entry;
      if (existing == null) {
        final me = await ref.read(currentUserProvider.future);
        await repo.create({...body, 'org': ?me?.org});
      } else {
        await repo.update(_spec.id(existing), body);
      }
      _spec.refresh(ref);
      if (!mounted) return;
      navigator.pop(true);
    } on RepositoryException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = errorMessage(l10n, e);
      });
    } on Object catch (error, stackTrace) {
      reportCaughtError(error, stackTrace);
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

    return guardUnsavedChanges(
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            top: AppSpacing.sm,
            bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
          ),
          child: Form(
            key: _formKey,
            onChanged: markDirty,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _isEditing ? _spec.editTitle(l10n) : _spec.newTitle(l10n),
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  controller: _label,
                  label: l10n.conditionLabelLabel,
                  prefixIcon: Icons.label_outline,
                  enabled: !_busy,
                  validator: Validators.required(l10n),
                ),
                if (_description case final description?) ...[
                  const SizedBox(height: AppSpacing.md),
                  AppTextField(
                    controller: description,
                    label: l10n.conditionDescriptionLabel,
                    enabled: !_busy,
                    minLines: 2,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                if (_spec.notifiable != null)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.conditionNotifiableLabel),
                    subtitle: Text(l10n.conditionNotifiableHelp),
                    value: _notifiable,
                    onChanged: _busy
                        ? null
                        : (v) {
                            setState(() => _notifiable = v);
                            markDirty();
                          },
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.conditionActiveLabel),
                  subtitle: Text(_spec.activeHelp(l10n)),
                  value: _active,
                  onChanged: _busy
                      ? null
                      : (v) {
                          setState(() => _active = v);
                          markDirty();
                        },
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
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
      ),
    );
  }
}
