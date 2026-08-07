import 'dart:async';

import 'package:federfall/core/realtime/live_refresh.dart';
// Prefixed: this file also needs `memberLabel` from `placements_providers`,
// which declares an `orgMembersProvider` of its own (the active-only handoff
// roster). The filter wants the FULL roster — see `_carerOptions`.
import 'package:federfall/features/admin/admin_providers.dart' as admin;
import 'package:federfall/features/animals/animal_avatar.dart';
import 'package:federfall/features/cases/animal_species_providers.dart';
import 'package:federfall/features/cases/carer_line.dart';
import 'package:federfall/features/cases/cases_browser.dart';
import 'package:federfall/features/cases/cases_labels.dart';
import 'package:federfall/features/cases/conditions/conditions_providers.dart';
import 'package:federfall/features/cases/pending_case_query.dart';
import 'package:federfall/features/cases/placements/placements_providers.dart';
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
/// rest of the filters (activity, species, outcome, diagnosis, admission-date
/// range) live behind a compact filter button so they don't dominate the
/// screen.
class CasesScreen extends ConsumerStatefulWidget {
  const CasesScreen({this.initialQuery, super.key});

  /// A filter seeded from deep-link route params (dashboard tap-through,
  /// ctw.6), e.g. `/cases?scope=all&status=ready_for_release`. Null for the
  /// plain tab.
  final CaseQuery? initialQuery;

  @override
  ConsumerState<CasesScreen> createState() => _CasesScreenState();
}

/// How long the search field waits for the typing to stop before asking the
/// server. Each keystroke is now a request, so this is the difference between
/// one query per pause and one per character.
const _searchDebounce = Duration(milliseconds: 300);

class _CasesScreenState extends ConsumerState<CasesScreen> {
  final _searchController = TextEditingController();
  final _scroll = ScrollController();
  late CaseQuery _query;

  /// Pending debounced search update, cancelled by the next keystroke.
  Timer? _searchTimer;

  /// The case id (if any) this screen has already auto-widened the scope for
  /// — so a manual switch back to "mine" while still viewing that same case
  /// isn't immediately overridden. Reset by moving on to a different case.
  String? _autoWidenedFor;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
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
    // A handed-over filter is not typing, so it takes effect at once — and the
    // cancel keeps a keystroke still in flight from overwriting it.
    _searchTimer?.cancel();
    _update(query);
    _clearPendingAfterFrame();
  }

  /// Debounces the search field: the query — and with it the request — only
  /// changes once the typing pauses.
  void _onSearchChanged(String text) {
    _searchTimer?.cancel();
    _searchTimer = Timer(_searchDebounce, () {
      if (mounted) _update(_query.copyWith(text: text));
    });
  }

  void _maybeLoadMore() {
    if (!_scroll.hasClients) return;
    // Within a screenful of the bottom. loadMore() is a no-op while a page is
    // in flight, so firing this on every scroll frame is safe.
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 600) {
      unawaited(ref.read(caseBrowseFeedProvider(_query).notifier).loadMore());
    }
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
    _searchTimer?.cancel();
    _scroll.dispose();
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
  ///
  /// The list is now server-filtered and paged, so "not in [loaded]" no longer
  /// proves the case is out of scope — it may simply be further down than the
  /// pages fetched so far. Widening anyway is the cheaper mistake: it is one
  /// toggle to undo, it happens at most once per case, and the alternative
  /// (asking the server whether this one case matches) is a request to answer
  /// a question about a case already open on screen.
  void _maybeWidenScopeForSelection(String? selectedId, List<Case> loaded) {
    if (selectedId == null || _query.allScope || _query.carer != null) return;
    if (_autoWidenedFor == selectedId) return;
    if (loaded.any((c) => c.id == selectedId)) return;
    _autoWidenedFor = selectedId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _update(_query.copyWith(allScope: true));
    });
  }

  void _clear() {
    _searchTimer?.cancel();
    _searchController.clear();
    _update(const CaseQuery());
  }

  Future<void> _openFilters() async {
    await showAppSheet<void>(
      context,
      builder: (_) => _FilterSheet(
        initial: _query,
        onChanged: _update,
        onClear: _clear,
      ),
    );
  }

  /// The app bar title for the current filter. A carer filter names whose
  /// caseload this is — arriving from the dashboard's workload card, "All
  /// cases" would read as though the tap had not taken. Only then is the roster
  /// read, so the plain tab still costs no `users` request.
  String _title(AppLocalizations l10n) {
    final carerId = _query.carer;
    if (carerId == null) {
      return _query.allScope ? l10n.casesAllTitle : l10n.casesTitle;
    }
    final members = ref.watch(admin.orgMembersProvider).value;
    final carer = members?.where((m) => m.id == carerId).firstOrNull;
    // Until the roster lands (or if the id is unknown) the honest fallback is
    // the widened scope this filter implies, not a name we don't have.
    return carer == null
        ? l10n.casesAllTitle
        : l10n.casesCarerTitle(memberLabel(carer));
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
      () => ref.invalidate(caseBrowseFeedProvider),
    );
    final feed = ref.watch(caseBrowseFeedProvider(_query));
    // The empty list offers an "admit a case" CTA of its own, so suppress the
    // FAB then — two identical primary actions on one screen is redundant.
    // Under a narrowed query the empty state is "no matches", which offers
    // nothing, so the FAB stays. Likewise while loading or on error.
    final showFab = _query.isNarrowed || (feed.value?.cases.isNotEmpty ?? true);

    return Scaffold(
      appBar: AppBar(
        title: Text(_title(l10n)),
        actions: const [AccountMenu()],
      ),
      floatingActionButton: showFab
          ? FloatingActionButton(
              onPressed: () => context.push(AppRoutes.newCase),
              tooltip: l10n.caseNewTitle,
              child: const Icon(Icons.add),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: _SearchBar(
              controller: _searchController,
              facetCount: _query.activeFacetCount,
              onChanged: _onSearchChanged,
              onOpenFilters: _openFilters,
            ),
          ),
          const Divider(height: 1),
          // Inside the Column, not around it: the search field has to stay put
          // while the results below it load, or typing loses focus on every
          // request.
          Expanded(
            child: AsyncValueView<CaseBrowseState>(
              value: feed,
              onRetry: () => ref.invalidate(caseBrowseFeedProvider(_query)),
              data: (state) => _results(state, selectedId),
            ),
          ),
        ],
      ),
    );
  }

  Widget _results(CaseBrowseState state, String? selectedId) {
    final l10n = context.l10n;
    _maybeWidenScopeForSelection(selectedId, state.cases);

    // `hasMore` with no rows is not emptiness: under the outcome facet a
    // server page can refine away entirely (federfall-etd7), and the answer is
    // still being read. Falling through to the list draws just the tail, which
    // fetches the next page — an EmptyView would end the search then and there.
    if (state.cases.isEmpty && !state.hasMore) {
      // Which emptiness this is can no longer be read off the loaded rows —
      // the server sent only what matched. The query itself says it: nothing
      // narrows the default view, so there is nothing to find.
      return _query.isNarrowed
          ? EmptyView(message: l10n.casesNoMatches)
          : EmptyView(
              icon: Icons.medical_information_outlined,
              title: l10n.casesEmpty,
              message: l10n.casesEmptyBody,
              actionLabel: l10n.casesEmptyAction,
              actionIcon: Icons.add,
              onAction: () => context.push(AppRoutes.newCase),
            );
    }

    return RefreshIndicator(
      onRefresh: () => ref.refresh(caseBrowseFeedProvider(_query).future),
      child: ListView.builder(
        controller: _scroll,
        // Always scrollable, so pull-to-refresh works on a short list.
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: state.cases.length + (state.hasMore ? 1 : 0),
        itemBuilder: (context, i) {
          if (i >= state.cases.length) {
            return PagedListTail(
              error: state.pageError,
              onLoad: () => unawaited(
                ref.read(caseBrowseFeedProvider(_query).notifier).loadMore(),
              ),
              onRetry: () => unawaited(
                ref.read(caseBrowseFeedProvider(_query).notifier).retryPage(),
              ),
            );
          }
          final c = state.cases[i];
          return _CaseTile(
            c,
            state.animalsById[c.animal],
            // Redundant in the "mine" scope — every case is already the
            // signed-in user's — and under a carer filter, where the app bar
            // already names them.
            showCarer: _query.allScope && _query.carer == null,
            selected: c.id == selectedId,
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

/// Whose cases the browser is showing: the signed-in user's, every case they
/// may access, or one named colleague's.
///
/// ONE picker, because these three were never independent. [CaseQuery.carer]
/// supersedes [CaseQuery.allScope] rather than intersecting with it — picking a
/// colleague while scoped to "mine" would otherwise yield nothing — which the
/// sheet used to express as a mine/all toggle that greyed itself out whenever a
/// colleague was named. Two controls for one question also made the default
/// read as a contradiction: the toggle said "Mine" while the carer picker
/// beside it said "Any carer".
@immutable
class _Caseload {
  const _Caseload.mine() : carerId = null, allScope = false;
  const _Caseload.all() : carerId = null, allScope = true;
  const _Caseload.of(String this.carerId) : allScope = false;

  /// The colleague whose caseload this names, or null for the mine/all
  /// entries.
  final String? carerId;
  final bool allScope;

  /// [query] pointed at this caseload. Both fields are always written, so
  /// leaving a colleague cannot strand the scope they were picked from.
  CaseQuery applyTo(CaseQuery query) {
    final id = carerId;
    return id == null
        ? query.copyWith(allScope: allScope, clearCarer: true)
        : query.copyWith(carer: id);
  }

  @override
  bool operator ==(Object other) =>
      other is _Caseload &&
      other.carerId == carerId &&
      other.allScope == allScope;

  @override
  int get hashCode => Object.hash(carerId, allScope);
}

/// Bottom sheet holding the secondary filters. Edits its own copy of the query
/// and pushes each change up live, so the list behind it updates immediately.
///
/// Every `DropdownMenu` here sets `requestFocusOnTap: false`. They are pickers
/// over a closed set — the caseloads, species, outcomes and diagnoses that
/// exist — so there is nothing a typed value could mean. Left at the default it
/// is editable on desktop/web (the flag resolves per platform: read-only on
/// Android/iOS, focusable elsewhere), and since none of them sets
/// `enableFilter`, typing only overwrites the label of a selection that is
/// still in force. The intake screen's species field is the deliberate
/// exception: there a new species is a legitimate free-text value.
class _FilterSheet extends ConsumerStatefulWidget {
  const _FilterSheet({
    required this.initial,
    required this.onChanged,
    required this.onClear,
  });

  final CaseQuery initial;
  final ValueChanged<CaseQuery> onChanged;
  final VoidCallback onClear;

  @override
  ConsumerState<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<_FilterSheet> {
  late CaseQuery _query = widget.initial;

  void _apply(CaseQuery query) {
    setState(() => _query = query);
    widget.onChanged(query);
  }

  /// Diagnoses offered by the filter: the ones actually recorded on cases
  /// (`condition_labels`), most-used first. Unlike the `conditions` code list
  /// this holds no entry that would filter to nothing, and it does include
  /// free-text diagnoses — and it is still one small row set, unlike the
  /// per-case rows `caseFacetsProvider` loads only once a facet is set.
  ///
  /// The server withholds free-text rows from members who cannot read the
  /// cases they were typed on, so a label handed over by a statistics
  /// tap-through is appended when the view didn't supply it — otherwise the
  /// dropdown would render an active filter as a blank the user can neither
  /// read nor clear.
  List<String> get _conditionOptions {
    final recorded =
        ref.watch(recordedConditionsProvider).value ?? const <ConditionLabel>[];
    final own = _query.condition;
    return [
      for (final c in recorded) c.label,
      if (own != null && !recorded.any((c) => c.label == own)) own,
    ];
  }

  /// Species offered by the filter: the org's recorded vocabulary, from the
  /// `animal_species` view — the same small row set the intake screen's
  /// species field reads.
  ///
  /// It used to be the distinct species among the loaded cases, which was only
  /// possible while the whole collection was on the device and was wrong at
  /// the edges anyway: a species held only by cases outside the current scope
  /// was not offered, so the filter could not reach them. As with the carer
  /// and diagnosis pickers, an active value the view didn't supply is appended
  /// rather than rendered as a blank the user can neither read nor clear.
  List<String> get _speciesOptions {
    final recorded = ref.watch(animalSpeciesProvider).value ?? const <String>[];
    final own = _query.species;
    return [
      ...recorded,
      if (own != null && !recorded.contains(own)) own,
    ];
  }

  /// Carers offered by the filter: the FULL roster, deactivated members
  /// included. Two reasons it isn't the active-only handoff list — filtering by
  /// a carer is not assigning to them, and a deactivated member can still hold
  /// open cases (only *deleting* one is blocked on their caseload), which is
  /// precisely the caseload someone goes looking for. It also keeps the
  /// dropdown able to name whatever the dashboard's workload card handed over,
  /// instead of rendering it as a blank the user can neither read nor clear.
  List<AppUser> get _carerOptions =>
      ref.watch(admin.orgMembersProvider).value ?? const [];

  /// Which caseload the current query names — the selected entry of the one
  /// picker that now covers mine / all / a colleague's.
  _Caseload get _caseload {
    final carerId = _query.carer;
    if (carerId != null) return _Caseload.of(carerId);
    return _query.allScope ? const _Caseload.all() : const _Caseload.mine();
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
    final carers = _carerOptions;
    final speciesOptions = _speciesOptions;

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
            _FilterLabel(l10n.casesCaseloadLabel),
            DropdownMenu<_Caseload>(
              initialSelection: _caseload,
              expandedInsets: EdgeInsets.zero,
              requestFocusOnTap: false,
              dropdownMenuEntries: [
                // The same words the app bar then shows, so the entry and the
                // title agree about which list this is.
                DropdownMenuEntry(
                  value: const _Caseload.mine(),
                  label: l10n.casesTitle,
                ),
                DropdownMenuEntry(
                  value: const _Caseload.all(),
                  label: l10n.casesAllTitle,
                ),
                for (final m in carers)
                  DropdownMenuEntry(
                    value: _Caseload.of(m.id),
                    label: memberLabel(m),
                  ),
              ],
              onSelected: (choice) {
                if (choice != null) _apply(choice.applyTo(_query));
              },
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
            if (speciesOptions.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              _FilterLabel(l10n.casesSpeciesLabel),
              DropdownMenu<String?>(
                initialSelection: _query.species,
                expandedInsets: EdgeInsets.zero,
                requestFocusOnTap: false,
                dropdownMenuEntries: [
                  DropdownMenuEntry(
                    value: null,
                    label: l10n.casesFilterSpeciesAny,
                  ),
                  for (final s in speciesOptions)
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
            _FilterLabel(l10n.dispositionFieldType),
            DropdownMenu<DispositionType?>(
              initialSelection: _query.outcome,
              expandedInsets: EdgeInsets.zero,
              requestFocusOnTap: false,
              dropdownMenuEntries: [
                DropdownMenuEntry(
                  value: null,
                  label: l10n.casesFilterOutcomeAny,
                ),
                for (final t in DispositionType.values)
                  DropdownMenuEntry(
                    value: t,
                    label: dispositionTypeLabel(l10n, t),
                  ),
              ],
              onSelected: (t) => _apply(
                t == null
                    ? _query.copyWith(clearOutcome: true)
                    : _query.copyWith(outcome: t),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _FilterLabel(l10n.conditionFieldName),
            DropdownMenu<String?>(
              initialSelection: _query.condition,
              expandedInsets: EdgeInsets.zero,
              requestFocusOnTap: false,
              dropdownMenuEntries: [
                DropdownMenuEntry(
                  value: null,
                  label: l10n.casesFilterConditionAny,
                ),
                for (final label in _conditionOptions)
                  DropdownMenuEntry(value: label, label: label),
              ],
              onSelected: (c) => _apply(
                c == null
                    ? _query.copyWith(clearCondition: true)
                    : _query.copyWith(condition: c),
              ),
            ),
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
