import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/areas/care_areas_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zugvogel_ui/zugvogel_ui.dart' show confirmAndDelete;

/// Opens the signed-in carer's area list (federfall-r67n), reached from the
/// case list's app bar.
Future<void> showCareAreasSheet(BuildContext context) =>
    showAppSheet<void>(context, builder: (_) => const CareAreasSheet());

/// Asks for an area's name; resolves to the trimmed name, or null when the
/// dialog is dismissed or left empty. Shared by the management sheet and the
/// case's area picker, which can create an area on the spot.
Future<String?> askCareAreaName(BuildContext context, {String? initial}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _AreaNameDialog(initial: initial),
    );

/// Creates an area of the signed-in user's at the end of their order and
/// returns it. The access rule pins `owner` to the caller, so it is sent as
/// exactly that.
Future<CareArea> createCareArea(WidgetRef ref, String name) async {
  final user = await ref.read(currentUserProvider.future);
  final org = user?.org;
  if (user == null || org == null) {
    throw const RepositoryException('no org for current user');
  }
  final repo = await ref.read(careAreasRepositoryProvider.future);
  // Read fresh rather than through the cached provider: the picker that also
  // calls this does not keep that provider alive, and a stale list would put
  // two rooms at the same position.
  final mine = areasOwnedBy(await repo.all(), user.id);
  final next = mine.isEmpty ? 0 : mine.last.position + 1;
  final created = await repo.create({
    'name': name,
    'position': next,
    'owner': user.id,
    'org': org,
  });
  ref.invalidate(careAreasProvider);
  return created;
}

/// The carer's own rooms: add, rename, delete, and drag into the order they
/// walk through them — which is the order the case list is grouped in.
///
/// Every change is written at once rather than behind a save button: each is a
/// single small record, and a list that is half-saved when the sheet is
/// swiped away would be the worse surprise.
class CareAreasSheet extends ConsumerStatefulWidget {
  const CareAreasSheet({super.key});

  @override
  ConsumerState<CareAreasSheet> createState() => _CareAreasSheetState();
}

class _CareAreasSheetState extends ConsumerState<CareAreasSheet> {
  /// The order just dragged into place, shown until the server's answer
  /// replaces it — without it the row snaps back for the length of a request.
  List<CareArea>? _pendingOrder;

  Future<void> _run(Future<void> Function() action) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
    } on Object catch (e, stackTrace) {
      reportCaughtError(e, stackTrace);
      messenger.showSnackBar(SnackBar(content: Text(errorMessage(l10n, e))));
    }
  }

  Future<void> _add() async {
    final name = await askCareAreaName(context);
    if (name == null) return;
    await _run(() => createCareArea(ref, name));
  }

  Future<void> _rename(CareArea area) async {
    final name = await askCareAreaName(context, initial: area.name);
    if (name == null || name == area.name) return;
    await _run(() async {
      final repo = await ref.read(careAreasRepositoryProvider.future);
      await repo.update(area.id, {'name': name});
      ref.invalidate(careAreasProvider);
    });
  }

  Future<void> _delete(CareArea area) {
    final l10n = context.l10n;
    // The server empties `area` on every case that named it (an optional,
    // non-cascading relation), so nothing else has to be cleaned up here.
    return confirmAndDelete(
      context,
      title: l10n.careAreaDeleteTitle,
      message: l10n.careAreaDeleteBody(area.name),
      confirmLabel: l10n.careAreaDelete,
      action: () async {
        final repo = await ref.read(careAreasRepositoryProvider.future);
        await repo.delete(area.id);
        ref.invalidate(careAreasProvider);
      },
    );
  }

  Future<void> _reorder(List<CareArea> areas, int from, int to) async {
    final order = [...areas];
    // `onReorderItem` already reports the index after the removal.
    order.insert(to, order.removeAt(from));
    setState(() => _pendingOrder = order);
    await _run(() async {
      final repo = await ref.read(careAreasRepositoryProvider.future);
      // Only the rows whose index changed — positions are dense from 0, so
      // a drag across two rows writes two records, not the whole list.
      for (var i = 0; i < order.length; i++) {
        if (order[i].position != i) {
          await repo.update(order[i].id, {'position': i});
        }
      }
      ref.invalidate(careAreasProvider);
      await ref.read(myCareAreasProvider.future);
    });
    if (mounted) setState(() => _pendingOrder = null);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final loaded = ref.watch(myCareAreasProvider);

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
            Text(l10n.careAreasTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.careAreasIntro,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Flexible(
              child: AsyncValueView<List<CareArea>>(
                value: loaded,
                onRetry: () => ref.invalidate(careAreasProvider),
                data: (fetched) {
                  final areas = _pendingOrder ?? fetched;
                  if (areas.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.md,
                      ),
                      child: Text(l10n.careAreasEmpty),
                    );
                  }
                  return ReorderableListView(
                    shrinkWrap: true,
                    buildDefaultDragHandles: false,
                    onReorderItem: (from, to) => _reorder(areas, from, to),
                    children: [
                      for (final (i, area) in areas.indexed)
                        ListTile(
                          key: ValueKey(area.id),
                          contentPadding: EdgeInsets.zero,
                          leading: ReorderableDragStartListener(
                            index: i,
                            child: const Icon(Icons.drag_handle),
                          ),
                          title: Text(area.name),
                          trailing: PopupMenuButton<void>(
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                onTap: () => _rename(area),
                                child: Text(l10n.careAreaRename),
                              ),
                              PopupMenuItem(
                                onTap: () => _delete(area),
                                child: Text(l10n.careAreaDelete),
                              ),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: _add,
              icon: const Icon(Icons.add),
              label: Text(l10n.careAreaAdd),
            ),
          ],
        ),
      ),
    );
  }
}

class _AreaNameDialog extends StatefulWidget {
  const _AreaNameDialog({this.initial});

  final String? initial;

  @override
  State<_AreaNameDialog> createState() => _AreaNameDialogState();
}

class _AreaNameDialogState extends State<_AreaNameDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    Navigator.of(context).pop(name.isEmpty ? null : name);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(
        widget.initial == null ? l10n.careAreaAdd : l10n.careAreaRename,
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 60,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: l10n.careAreaFieldName),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.actionSave)),
      ],
    );
  }
}
