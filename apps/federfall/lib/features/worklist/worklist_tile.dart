import 'dart:async';

import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall/features/cases/medications/administration_sheet.dart';
import 'package:federfall/features/cases/weights/weights_providers.dart';
import 'package:federfall/features/worklist/worklist.dart';
import 'package:federfall/features/worklist/worklist_dismissals.dart';
import 'package:federfall/features/worklist/worklist_labels.dart';
import 'package:federfall/features/worklist/worklist_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/routing/app_routes.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zugvogel_ui/zugvogel_ui.dart' show runQuickAction;

/// The alternatives a row offers behind its `⋮`, beside its one-tap verb.
enum _RowAction { adjustDose, cancelAppointment }

/// One worklist row: kind icon, case number, and a relative detail line that
/// turns error-coloured when overdue. Taps through to the case.
///
/// **Every kind has a verb** (federfall-78k6.3). A carer's complaint about this
/// list was that exactly one of its kinds could be finished from it; the rest
/// showed a chevron, which only ever meant "we did not think about this kind".
/// So the trailing control is the act itself — give the dose, mark the visit
/// kept, tick the recheck off — and the chevron is gone. The row is still
/// tappable, so nothing was lost with it.
///
/// The two writes that are not simply a stamp keep an escape hatch in a `⋮`
/// beside the verb: a partial dose or a different time goes through the
/// administration sheet, and an appointment that did not happen is cancelled
/// rather than attended. Long-press was considered for these and rejected —
/// undiscoverable is not the same as out of the way.
///
/// Anything written from here is confirmed with an **undo** snackbar rather
/// than a confirmation before the fact. That trade is what buys the single tap:
/// the cost of a mis-tap is one more tap, and the writes are all trivially
/// reversible (delete the administration, clear the stamp).
class WorklistTile extends ConsumerStatefulWidget {
  const WorklistTile({
    required this.item,
    required this.now,
    this.onTap,
    this.selected = false,
    this.showDrug = true,
    super.key,
  });

  final WorklistItem item;
  final DateTime now;

  /// Whether a medication row names its drug. False under a per-drug heading
  /// (federfall-o3gz), where repeating the name on every row of the group says
  /// nothing and crowds out the due time.
  final bool showDrug;

  /// Overrides the default tap behaviour (deep-link to the case). Supplied by
  /// the wide-screen Today layout to drive its side detail pane instead.
  final VoidCallback? onTap;

  /// Highlighted when its case is open in the adjacent pane (two-pane).
  final bool selected;

  @override
  ConsumerState<WorklistTile> createState() => _WorklistTileState();
}

class _WorklistTileState extends ConsumerState<WorklistTile> {
  /// Set the moment a swipe completes, so this row stops rendering before the
  /// list it belongs to has re-derived itself. Without it Dismissible finds its
  /// own dismissed child still in the tree on the next frame and throws.
  bool _swiped = false;

  WorklistItem get item => widget.item;

  // ---------------------------------------------------------------- writes

  /// Logs the planned dose in one tap, or hands over to the sheet when the plan
  /// does not determine a number on its own.
  Future<void> _giveDose() async {
    final plan = item.medication;
    if (plan == null) return _openDoseSheet();

    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final container = _container;
    await runQuickAction(context, () async {
      final derived = await _derivedDose(plan);
      if (derived == null) {
        // No number this path may write by itself — the sheet asks for one.
        if (mounted) await _openDoseSheet();
        return;
      }
      final user = await ref.read(currentUserProvider.future);
      final org = user?.org;
      if (user == null || org == null) {
        throw const RepositoryException('no org for current user');
      }
      final repo = await ref.read(
        medicationAdministrationsRepositoryProvider.future,
      );
      final written = await repo.create({
        'case': item.caseId,
        'medication': plan.id,
        'drug': plan.drug,
        'dose': derived.amount,
        'dose_unit': plan.doseUnit ?? '',
        'weight_g_used': derived.weightGUsed,
        'volume_ml': derived.volumeMl,
        'route': plan.route ?? '',
        'administered_at': DateTime.now().toUtc().toIso8601String(),
        'notes': '',
        'administered_by': user.id,
        'org': org,
      });
      _refreshCase(container);
      _offerUndo(messenger, l10n, l10n.worklistDoseLogged, () async {
        await repo.delete(written.id);
        _refreshCase(container);
      });
    });
  }

  /// What one tap would record: the prescription's flat dose, or the amount its
  /// per-kilogram rate resolves to against a weight worth trusting. Null when
  /// the plan determines neither.
  ///
  /// A rate is only resolved from a CURRENT weight, and any warning at all
  /// stops it: no weight and a stale one are the two cases where a number would
  /// be a guess, and an unmeasurable volume needs a dilution somebody has to
  /// choose. The batch sheet declines to prefill on exactly the same grounds —
  /// one tap must be at least as careful as a form the carer still reads.
  Future<({double amount, double? weightGUsed, double? volumeMl})?>
  _derivedDose(Medication plan) async {
    final rate = plan.doseRate;
    if (rate == null) {
      final dose = plan.dose;
      if (dose == null) return null;
      return (amount: dose, weightGUsed: null, volumeMl: null);
    }
    final repo = await ref.read(weightsRepositoryProvider.future);
    final weight = latestWeight(await repo.forCase(item.caseId));
    final result = calculateDose(
      rate: rate,
      weightG: weight?.weightG,
      weighedAt: weight?.measuredAt ?? weight?.created,
      concentrationPerMl: plan.concentrationPerMl,
    );
    if (!result.hasAmount || result.warnings.isNotEmpty) return null;
    return (
      amount: result.amount!,
      weightGUsed: weight?.weightG,
      volumeMl: result.volumeMl,
    );
  }

  Future<void> _openDoseSheet() async {
    final saved = await showAdministrationSheet(
      context,
      caseId: item.caseId,
      plan: item.medication,
    );
    if (!(saved ?? false) || !mounted) return;
    _refreshCase(_container);
  }

  Future<void> _markFollowUpDone() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final container = _container;
    await runQuickAction(context, () async {
      final repo = await ref.read(followUpsRepositoryProvider.future);
      final id = item.followUp!.id;
      await repo.update(id, {
        'done_at': DateTime.now().toUtc().toIso8601String(),
      });
      _refreshCase(container);
      _offerUndo(messenger, l10n, l10n.worklistFollowUpDone, () async {
        await repo.update(id, {'done_at': ''});
        _refreshCase(container);
      });
    });
  }

  /// Stamps an appointment attended or cancelled. Both are the same write with
  /// a different field, exactly as on the case's own appointment tile.
  Future<void> _stampAppointment({
    required String field,
    required String confirmation,
  }) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final container = _container;
    await runQuickAction(context, () async {
      final repo = await ref.read(vetAppointmentsRepositoryProvider.future);
      final id = item.appointment!.id;
      await repo.update(id, {
        field: DateTime.now().toUtc().toIso8601String(),
      });
      _refreshCase(container);
      _offerUndo(messenger, l10n, confirmation, () async {
        await repo.update(id, {field: ''});
        _refreshCase(container);
      });
    });
  }

  /// Hides the row for the rest of the day. Writes nothing to the server — see
  /// [WorklistDismissals] for why that is the whole point.
  Future<void> _dismiss() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final key = worklistDismissalKey(item);
    final dismissals = ref.read(worklistDismissalsProvider.notifier);
    await dismissals.dismiss(key);
    // No mounted check: the row is normally gone by now — that is the point —
    // and the undo has to be offered anyway.
    _offerUndo(
      messenger,
      l10n,
      l10n.worklistDismissed,
      () => dismissals.restore(key),
    );
  }

  /// Re-reads the case and the worklist after a write.
  ///
  /// Takes the container rather than using [ref] because half of these calls
  /// happen from an undo, and by then the row is usually gone: a `ref` belongs
  /// to the element and throws once that is disposed. The container outlives
  /// every row in the list.
  void _refreshCase(ProviderContainer container) => container
    ..invalidate(caseBundleProvider(item.caseId))
    ..invalidate(worklistSourceProvider);

  /// The scope's container, captured while the row is still mounted.
  ProviderContainer get _container =>
      ProviderScope.containerOf(context, listen: false);

  /// Confirms a completed write and offers to take it back.
  ///
  /// Messenger and strings are passed in rather than read from `context`: the
  /// row usually leaves the tree the instant the worklist re-derives, and the
  /// snackbar has to outlive it. For the same reason the undo reports its own
  /// failure here instead of through [runQuickAction], which needs a context.
  void _offerUndo(
    ScaffoldMessengerState messenger,
    AppLocalizations l10n,
    String message,
    Future<void> Function() undo,
  ) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          action: SnackBarAction(
            label: l10n.actionUndo,
            onPressed: () async {
              try {
                await undo();
              } on Object catch (error, stackTrace) {
                reportCaughtError(error, stackTrace);
                messenger.showSnackBar(
                  SnackBar(content: Text(errorMessage(l10n, error))),
                );
              }
            },
          ),
        ),
      );
  }

  // ------------------------------------------------------------------- ui

  @override
  Widget build(BuildContext context) {
    if (_swiped) return const SizedBox.shrink();

    final l10n = context.l10n;
    final theme = Theme.of(context);
    final overdue = item.severity == WorklistSeverity.overdue;

    return Dismissible(
      key: ValueKey('worklist-swipe-${worklistDismissalKey(item)}'),
      background: const _SwipeBackground(alignment: Alignment.centerLeft),
      secondaryBackground: const _SwipeBackground(
        alignment: Alignment.centerRight,
      ),
      onDismissed: (_) {
        setState(() => _swiped = true);
        unawaited(_dismiss());
      },
      child: ListTile(
        selected: widget.selected,
        leading: Icon(worklistIcon(item.kind)),
        title: Text(worklistItemTitle(l10n, item)),
        subtitle: Text(
          worklistItemDetail(l10n, item, widget.now, showDrug: widget.showDrug),
          style: overdue
              ? theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                )
              : null,
        ),
        trailing: _trailing(l10n),
        onTap:
            widget.onTap ?? () => context.go(AppRoutes.caseDetail(item.caseId)),
      ),
    );
  }

  /// The row's verb, plus a `⋮` where the kind has a second answer.
  Widget? _trailing(AppLocalizations l10n) {
    final verb = _verb(l10n);
    final actions = _actions(l10n);
    if (actions.isEmpty) return verb;
    final menu = PopupMenuButton<_RowAction>(
      tooltip: l10n.worklistMoreActions,
      onSelected: _onAction,
      itemBuilder: (_) => actions,
    );
    if (verb == null) return menu;
    return Row(mainAxisSize: MainAxisSize.min, children: [verb, menu]);
  }

  Widget? _verb(AppLocalizations l10n) => switch (item.kind) {
    WorklistKind.medicationDue => IconButton(
      icon: const Icon(Icons.vaccines_outlined),
      tooltip: l10n.worklistLogDose,
      onPressed: _giveDose,
    ),
    WorklistKind.followUpDue when item.followUp != null => IconButton(
      icon: const Icon(Icons.check_circle_outline),
      tooltip: l10n.followUpMarkDone,
      onPressed: _markFollowUpDone,
    ),
    WorklistKind.vetAppointment when item.appointment != null => IconButton(
      icon: const Icon(Icons.check_circle_outline),
      tooltip: l10n.vetAppointmentMarkAttended,
      onPressed: () => _stampAppointment(
        field: 'attended_at',
        confirmation: l10n.worklistAppointmentAttendedDone,
      ),
    ),
    // A quarantine ending is a notice, not an obligation: "end it now" would
    // write today's date, which is the date it already carries, and the row
    // would sit there looking untouched until it lapsed tomorrow anyway. So the
    // verb here is the acknowledgement — the same one the swipe performs.
    WorklistKind.quarantineEnding => IconButton(
      icon: const Icon(Icons.check_circle_outline),
      tooltip: l10n.worklistAcknowledge,
      onPressed: _dismiss,
    ),
    _ => null,
  };

  List<PopupMenuEntry<_RowAction>> _actions(AppLocalizations l10n) =>
      switch (item.kind) {
        WorklistKind.medicationDue when item.medication != null => [
          PopupMenuItem(
            value: _RowAction.adjustDose,
            child: Text(l10n.worklistDoseAdjust),
          ),
        ],
        WorklistKind.vetAppointment when item.appointment != null => [
          PopupMenuItem(
            value: _RowAction.cancelAppointment,
            child: Text(l10n.vetAppointmentCancel),
          ),
        ],
        _ => const [],
      };

  void _onAction(_RowAction action) {
    switch (action) {
      case _RowAction.adjustDose:
        unawaited(_openDoseSheet());
      case _RowAction.cancelAppointment:
        unawaited(
          _stampAppointment(
            field: 'cancelled_at',
            confirmation: context.l10n.worklistAppointmentCancelledDone,
          ),
        );
    }
  }
}

/// What shows behind a row being swiped away: the same neutral surface either
/// way, because the gesture means the same thing in both directions.
class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({required this.alignment});

  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Align(
        alignment: alignment,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Icon(
            Icons.visibility_off_outlined,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
