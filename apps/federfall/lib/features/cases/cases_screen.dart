import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/core/realtime/live_refresh.dart';
import 'package:federfall/features/animals/animal_avatar.dart';
import 'package:federfall/features/cases/cases_browser.dart';
import 'package:federfall/features/cases/cases_labels.dart';
import 'package:federfall/features/home/account_menu.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/routing/app_routes.dart';
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
  late CaseQuery _query = widget.initialQuery ?? const CaseQuery();

  @override
  void initState() {
    super.initState();
    _searchController.text = _query.text;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _update(CaseQuery query) => setState(() => _query = query);

  void _clear() {
    _searchController.clear();
    _update(const CaseQuery());
  }

  Future<void> _openFilters(List<String> speciesOptions) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
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
    // 'case_shares' matters because a case shared *with* the signed-in user
    // grants list visibility without touching the case record itself — so only
    // the case_shares create/delete event reflects the change live.
    ref.liveRefresh(
      const ['cases', 'animals', 'case_shares'],
      () => ref.invalidate(casesBrowserDataProvider),
    );
    final data = ref.watch(casesBrowserDataProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_query.allScope ? l10n.casesAllTitle : l10n.casesTitle),
        actions: const [AccountMenu()],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.go(AppRoutes.newCase),
        tooltip: l10n.caseNewTitle,
        child: const Icon(Icons.add),
      ),
      body: AsyncValueView<CasesBrowserData>(
        value: data,
        onRetry: () => ref.invalidate(casesBrowserDataProvider),
        errorMessage: (e) => errorMessage(l10n, e),
        data: (d) {
          final results = filterCases(
            d.cases,
            d.animalsById,
            myUserId: d.myUserId,
            query: _query,
          );
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
                    ? EmptyView(message: l10n.casesEmpty)
                    : results.isEmpty
                    ? EmptyView(message: l10n.casesNoMatches)
                    : RefreshIndicator(
                        onRefresh: () =>
                            ref.refresh(casesBrowserDataProvider.future),
                        child: ListView.builder(
                          itemCount: results.length,
                          itemBuilder: (context, i) {
                            final c = results[i];
                            return _CaseTile(c, d.animalsById[c.animal]);
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
  const _CaseTile(this.medicalCase, this.animal);

  final Case medicalCase;
  final Animal? animal;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final status = medicalCase.status;
    final subtitle = [
      ?_animalLabel,
      if (status != null) caseStatusLabel(l10n, status),
    ].join(' · ');

    return ListTile(
      leading: AnimalAvatar(animalId: medicalCase.animal, radius: 20),
      title: Text(medicalCase.caseNumber ?? l10n.caseNewTitle),
      subtitle: subtitle.isEmpty ? null : Text(subtitle),
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
