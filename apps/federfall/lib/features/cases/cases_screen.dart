import 'package:federfall/core/realtime/live_refresh.dart';
import 'package:federfall/features/animals/animal_avatar.dart';
import 'package:federfall/features/cases/carer_line.dart';
import 'package:federfall/features/cases/cases_browser.dart';
import 'package:federfall/features/cases/cases_labels.dart';
import 'package:federfall/features/cases/pending_case_query.dart';
import 'package:federfall/features/home/account_menu.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/routing/app_routes.dart';
import 'package:federfall/routing/route_selection.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// All-cases browser (FED-7.4): the Cases tab of the navigation shell.
///
/// Defaults to the carer's own active cases; a scope toggle widens to every
/// case they may access (server-scoped). The search field stays visible; the
/// rest of the filters (activity, species, admission-date range) live behind a
/// compact filter button so they don't dominate the screen.
class CasesScreen extends ConsumerStatefulWidget {
  const CasesScreen({this.initialQuery, super.key});

  /// A filter seeded from deep-link route params (dashboard tap-through,
  /// ctw.6), e.g. `/cases?scope=all&status=ready_for_release`. Null for the
  /// plain tab.
  final CaseQuery? initialQuery;

  @override
  ConsumerState<CasesScreen> createState() => _CasesScreenState();
}

class _CasesScreenState extends ConsumerState<CasesScreen> {
  final _searchController = TextEditingController();
  late CaseQuery _query;

  /// The case id (if any) this screen has already auto-widened the scope for
  /// — so a manual switch back to "mine" while still viewing that same case
  /// isn't immediately overridden. Reset by moving on to a different case.
  String? _autoWidenedFor;

  @override
  void initState() {
    super.initState();
    // A dashboard KPI (or the nav menu) hands a filter off via the
    // pending-query provider when switching to this tab (the tab's state
    // survives, so a route query can't re-seed a live screen). Consume it once
    // on mount; it wins over the (deep-link) initialQuery and the default.
    // Providers can't be modified during initState, so clear after first frame.
    final pending = ref.read(pendingCaseQueryProvider);
    _query = pending ?? widget.initialQuery ?? const CaseQuery();
    _searchController.text = _query.text;
    if (pending != null) _clearPendingAfterFrame();
  }

  /// Apply a filter handed in via [pendingCaseQueryProvider] while this screen
  /// is already alive (the cases tab was visited before), then clear it.
  void _applyPending(CaseQuery query) {
    _searchController.text = query.text;
    _update(query);
    _clearPendingAfterFrame();
  }

  /// Clear the pending filter once consumed — deferred so it never mutates the
  /// provider during a build / listener pass.
  void _clearPendingAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(pendingCaseQueryProvider.notifier).clear();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _update(CaseQuery query) => setState(() => _query = query);

  /// Opening a case from outside this screen (dashboard KPI, animal history,
  /// worklist, notification, deep link, ...) can land on a case the current
  /// "mine" scope excludes. Most noticeable on the expanded two-pane layout,
  /// where the list sits right next to the open detail — the case would
  /// otherwise look absent from its own list. Widen to "all cases" once per
  /// case so it stays visible/highlighted; deferred so it never mutates state
  /// during build.
  void _maybeWidenScopeForSelection(
    String? selectedId,
    List<Case> filtered,
    List<Case> accessible,
  ) {
    if (selectedId == null || _query.allScope) return;
    if (_autoWidenedFor == selectedId) return;
    if (filtered.any((c) => c.id == selectedId)) return;
    if (!accessible.any((c) => c.id == selectedId)) return;
    _autoWidenedFor = selectedId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _update(_query.copyWith(allScope: true));
    });
  }

  void _clear() {
    _searchController.clear();
    _update(const CaseQuery());
  }

  Future<void> _openFilters(List<String> speciesOptions) async {
    await showAppSheet<void>(
      context,
      builder: (_) => _FilterSheet(
        initial: _query,
        speciesOptions: speciesOptions,
        onChanged: _update,
        onClear: _clear,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // If a KPI sets a pending filter while this tab is already alive, apply it.
    ref.listen(pendingCaseQueryProvider, (_, next) {
      if (next != null) _applyPending(next);
    });
    // The case open in the detail pane (expanded two-pane), so its row reads as
    // selected. Null on compact / when nothing is open.
    final selectedId = selectedDetailId(context);
    // 'case_shares' matters because a case shared *with* the signed-in user
    // grants list visibility without touching the case record itself — so only
    // the case_shares create/delete event reflects the change live.
    ref.liveRefresh(
      const ['cases', 'animals', 'case_shares'],
      () => ref.invalidate(casesBrowserDataProvider),
    );
    final data = ref.watch(casesBrowserDataProvider);
    // When the list is empty its empty-state already offers an "admit a case"
    // CTA, so suppress the FAB then — two identical primary actions on one
    // screen is redundant. While loading or on error (no known list) keep it.
    final showFab = data.value?.cases.isNotEmpty ?? true;

    return Scaffold(
      appBar: AppBar(
        title: Text(_query.allScope ? l10n.casesAllTitle : l10n.casesTitle),
        actions: const [AccountMenu()],
      ),
      floatingActionButton: showFab
          ? FloatingActionButton(
              onPressed: () => context.push(AppRoutes.newCase),
              tooltip: l10n.caseNewTitle,
              child: const Icon(Icons.add),
            )
          : null,
      body: AsyncValueView<CasesBrowserData>(
        value: data,
        onRetry: () => ref.invalidate(casesBrowserDataProvider),
        data: (d) {
          final results = filterCases(
            d.cases,
            d.animalsById,
            myUserId: d.myUserId,
            query: _query,
            codesByAnimal: d.codesByAnimal,
          );
          _maybeWidenScopeForSelection(selectedId, results, d.cases);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: _SearchBar(
                  controller: _searchController,
                  facetCount: _query.activeFacetCount,
                  onChanged: (v) => _update(_query.copyWith(text: v)),
                  onOpenFilters: () => _openFilters(d.speciesOptions),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: d.cases.isEmpty
                    ? EmptyView(
                        icon: Icons.medical_information_outlined,
                        title: l10n.casesEmpty,
                        message: l10n.casesEmptyBody,
                        actionLabel: l10n.casesEmptyAction,
                        actionIcon: Icons.add,
                        onAction: () => context.push(AppRoutes.newCase),
                      )
                    : results.isEmpty
                    ? EmptyView(message: l10n.casesNoMatches)
                    : RefreshIndicator(
                        onRefresh: () =>
                            ref.refresh(casesBrowserDataProvider.future),
                        child: ListView.builder(
                          itemCount: results.length,
                          itemBuilder: (context, i) {
                            final c = results[i];
                            return _CaseTile(
                              c,
                              d.animalsById[c.animal],
                              // Redundant in the "mine" scope — every case is
                              // already the signed-in user's.
                              showCarer: _query.allScope,
                              selected: c.id == selectedId,
                            );
                          },
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.facetCount,
    required this.onChanged,
    required this.onOpenFilters,
  });

  final TextEditingController controller;
  final int facetCount;
  final ValueChanged<String> onChanged;
  final VoidCallback onOpenFilters;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: l10n.casesSearchHint,
              isDense: true,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        IconButton.filledTonal(
          tooltip: l10n.casesFiltersTitle,
          onPressed: onOpenFilters,
          icon: Badge(
            isLabelVisible: facetCount > 0,
            label: Text('$facetCount'),
            child: const Icon(Icons.tune),
          ),
        ),
      ],
    );
  }
}

/// Bottom sheet holding the secondary filters. Edits its own copy of the query
/// and pushes each change up live, so the list behind it updates immediately.
class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
    required this.initial,
    required this.speciesOptions,
    required this.onChanged,
    required this.onClear,
  });

  final CaseQuery initial;
  final List<String> speciesOptions;
  final ValueChanged<CaseQuery> onChanged;
  final VoidCallback onClear;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late CaseQuery _query = widget.initial;

  void _apply(CaseQuery query) {
    setState(() => _query = query);
    widget.onChanged(query);
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _query.admittedRange,
    );
    if (picked != null) _apply(_query.copyWith(admittedRange: picked));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final range = _query.admittedRange;

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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(l10n.casesFiltersTitle, style: theme.textTheme.titleLarge),
                const Spacer(),
                if (_query.isNarrowed)
                  TextButton(
                    onPressed: () {
                      widget.onClear();
                      Navigator.of(context).pop();
                    },
                    child: Text(l10n.casesClearFilters),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _FilterLabel(l10n.casesScopeLabel),
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: false, label: Text(l10n.casesScopeMine)),
                ButtonSegment(value: true, label: Text(l10n.casesScopeAll)),
              ],
              selected: {_query.allScope},
              onSelectionChanged: (s) =>
                  _apply(_query.copyWith(allScope: s.first)),
            ),
            const SizedBox(height: AppSpacing.md),
            _FilterLabel(l10n.casesActivityLabel),
            SegmentedButton<CaseActivity>(
              segments: [
                ButtonSegment(
                  value: CaseActivity.active,
                  label: Text(l10n.casesActivityActive),
                ),
                ButtonSegment(
                  value: CaseActivity.closed,
                  label: Text(l10n.casesActivityClosed),
                ),
                ButtonSegment(
                  value: CaseActivity.all,
                  label: Text(l10n.casesActivityAll),
                ),
              ],
              selected: {_query.activity},
              onSelectionChanged: (s) =>
                  _apply(_query.copyWith(activity: s.first)),
            ),
            if (widget.speciesOptions.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              _FilterLabel(l10n.casesSpeciesLabel),
              DropdownMenu<String?>(
                initialSelection: _query.species,
                expandedInsets: EdgeInsets.zero,
                dropdownMenuEntries: [
                  DropdownMenuEntry(
                    value: null,
                    label: l10n.casesFilterSpeciesAny,
                  ),
                  for (final s in widget.speciesOptions)
                    DropdownMenuEntry(value: s, label: s),
                ],
                onSelected: (s) => _apply(
                  s == null
                      ? _query.copyWith(clearSpecies: true)
                      : _query.copyWith(species: s),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            _FilterLabel(l10n.casesFilterDateRange),
            Align(
              alignment: Alignment.centerLeft,
              child: InputChip(
                avatar: const Icon(Icons.date_range, size: 18),
                label: Text(
                  range == null
                      ? l10n.casesDateRangeAny
                      : '${_fmt(range.start)} – ${_fmt(range.end)}',
                ),
                onPressed: _pickDateRange,
                onDeleted: range == null
                    ? null
                    : () => _apply(_query.copyWith(clearRange: true)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterLabel extends StatelessWidget {
  const _FilterLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
    child: Text(text, style: Theme.of(context).textTheme.labelLarge),
  );
}

/// `yyyy-MM-dd` for the date-range chip (locale-independent, compact).
String _fmt(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

class _CaseTile extends StatelessWidget {
  const _CaseTile(
    this.medicalCase,
    this.animal, {
    this.showCarer = false,
    this.selected = false,
  });

  final Case medicalCase;
  final Animal? animal;

  /// Whether to name the active carer (only useful in the all-cases scope; in
  /// "mine" every case is the signed-in user's, so it would be redundant).
  final bool showCarer;

  /// Highlighted when its detail is open in the adjacent pane (two-pane).
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final status = medicalCase.status;
    // An unnumbered case is titled by its animal instead of a placeholder —
    // "Neuer Fall" in the list read like a create action (federfall-dai). The
    // animal then leaves the subtitle so it isn't shown twice.
    final number = medicalCase.caseNumber;
    final title = number ?? _animalLabel ?? l10n.worklistUnnumberedCase;
    final summary = [
      if (number != null) ?_animalLabel,
      if (status != null) caseStatusLabel(l10n, status),
    ].join(' · ');
    final carerId = medicalCase.activeCarer;
    final hasCarer = showCarer && carerId != null && carerId.isNotEmpty;

    return ListTile(
      selected: selected,
      isThreeLine: hasCarer,
      leading: AnimalAvatar(animalId: medicalCase.animal, radius: 20),
      title: Text(title),
      subtitle: summary.isEmpty && !hasCarer
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (summary.isNotEmpty) Text(summary),
                if (hasCarer) CarerLine(carerId),
              ],
            ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.go(AppRoutes.caseDetail(medicalCase.id)),
    );
  }

  /// "Name · Species" (or just species) for the animal behind the case.
  String? get _animalLabel {
    final a = animal;
    if (a == null) return null;
    final name = a.name;
    if (name != null && name.isNotEmpty) {
      return a.species.isEmpty ? name : '$name · ${a.species}';
    }
    return a.species.isEmpty ? null : a.species;
  }
}
