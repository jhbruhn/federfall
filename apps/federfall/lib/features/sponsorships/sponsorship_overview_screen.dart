import 'dart:async';

import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/auth/roles.dart';
import 'package:federfall/features/animals/animals_providers.dart';
import 'package:federfall/features/aviaries/sponsorship_detail_sheet.dart';
import 'package:federfall/features/cases/cases_labels.dart';
import 'package:federfall/features/sponsorships/sponsorship_overview_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/routing/back_or_home.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Every Patenschaft in the org, for coordinators and supervisors
/// (federfall-ys7z).
///
/// A patronage is otherwise only reachable through the bird it belongs to,
/// where access resolves through `animal.current_aviary.keeper` — right for a
/// keeper, and no use to the role that has to answer who is currently
/// sponsoring, what that comes to, and whose patronage has lapsed. It is also
/// the only place the rows NO keeper can reach are visible at all: a bird that
/// has left aviary care, or an orphan whose bird was deleted (kept on purpose,
/// federfall-5s5j.4).
///
/// Gated on [canViewReports], which is exactly the `COORD_SUP` branch of
/// 1700000085's read rule. The role is re-checked here so a typed-in URL
/// degrades to a refusal rather than to a heading about data the reader may not
/// see; the rule stays the real boundary.
///
/// Every row is a private person's name, address and mobile, so two things this
/// screen deliberately does NOT do: there is no export (a spreadsheet of donor
/// contact details leaving the app is its own decision, and `report.exported`
/// would have to cover it), and nothing here is logged — reading is not an
/// audited act anywhere in this app, and auditing it would write sponsor names
/// into a table nothing can delete from, which is what `SENSITIVE.sponsorships`
/// exists to prevent.
class SponsorshipOverviewScreen extends ConsumerStatefulWidget {
  const SponsorshipOverviewScreen({super.key});

  @override
  ConsumerState<SponsorshipOverviewScreen> createState() =>
      _SponsorshipOverviewScreenState();
}

/// How long the search field waits for the typing to stop before asking the
/// server — a keystroke here is a request (federfall-trep).
const _searchDebounce = Duration(milliseconds: 300);

class _SponsorshipOverviewScreenState
    extends ConsumerState<SponsorshipOverviewScreen> {
  final _searchController = TextEditingController();
  final _scroll = ScrollController();
  SponsorshipQuery _query = const SponsorshipQuery();
  Timer? _searchTimer;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _scroll.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String text) {
    _searchTimer?.cancel();
    _searchTimer = Timer(_searchDebounce, () {
      if (mounted) setState(() => _query = _query.copyWith(text: text));
    });
  }

  void _maybeLoadMore() {
    if (!_scroll.hasClients) return;
    // Within a screenful of the bottom. loadMore() is a no-op while a page is
    // in flight, so firing this on every scroll frame is safe.
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 600) {
      unawaited(
        ref.read(sponsorshipOverviewFeedProvider(_query).notifier).loadMore(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final role = ref.watch(currentUserProvider).value?.role;

    if (!canViewReports(role)) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.sponsorshipsOverviewTitle)),
        body: EmptyView(
          icon: Icons.lock_outline,
          message: l10n.errorUnauthorized,
        ),
      );
    }

    final feed = ref.watch(sponsorshipOverviewFeedProvider(_query));

    return Scaffold(
      appBar: AppBar(
        // Pushed over the app, so a cold open has nothing to pop back to.
        leading: const BackOrHomeButton(),
        title: Text(l10n.sponsorshipsOverviewTitle),
      ),
      body: ContentBounds(
        child: Column(
          children: [
            const _Totals(),
            _Filters(
              controller: _searchController,
              query: _query,
              onSearch: _onSearchChanged,
              onQuery: (q) => setState(() => _query = q),
            ),
            const Divider(height: 1),
            // Inside the Column, not around it: the search field and the facets
            // have to stay put while the results below them load, or typing
            // loses focus on every request.
            Expanded(
              child: AsyncValueView<SponsorshipOverviewState>(
                value: feed,
                onRetry: () =>
                    ref.invalidate(sponsorshipOverviewFeedProvider(_query)),
                data: _results,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _results(SponsorshipOverviewState state) {
    final l10n = context.l10n;
    if (state.rows.isEmpty) {
      // Which emptiness this is cannot be read off the loaded rows — the server
      // sent only what matched. The query itself says it: nothing narrows the
      // default view, so there is nothing to find.
      return _query.isNarrowed
          ? EmptyView(message: l10n.sponsorshipsOverviewNoMatches)
          : EmptyView(
              icon: Icons.volunteer_activism_outlined,
              title: l10n.sponsorshipsOverviewEmpty,
              message: l10n.sponsorshipsOverviewEmptyBody,
            );
    }
    return RefreshIndicator(
      onRefresh: () =>
          ref.refresh(sponsorshipOverviewFeedProvider(_query).future),
      child: ListView.builder(
        controller: _scroll,
        // Always scrollable, so pull-to-refresh works on a short list.
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: state.rows.length + (state.hasMore ? 1 : 0),
        itemBuilder: (context, i) {
          if (i >= state.rows.length) {
            final notifier = ref.read(
              sponsorshipOverviewFeedProvider(_query).notifier,
            );
            return PagedListTail(
              error: state.pageError,
              onLoad: () => unawaited(notifier.loadMore()),
              onRetry: () => unawaited(notifier.retryPage()),
            );
          }
          return _SponsorshipTile(state.rows[i]);
        },
      ),
    );
  }
}

/// What the org's patronages currently come to.
///
/// Renders nothing at all while it loads, and nothing when there is no figure:
/// this sits above a list in the same scroll-free column, so a spinner would
/// shove the facets and the first rows down and then back up again — the
/// dashboard cards' habit, for the same reason. A failed read is silent too:
/// the list below is the screen's subject, and an error banner over a working
/// list would be the loudest thing on it.
class _Totals extends ConsumerWidget {
  const _Totals();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final totals = ref.watch(sponsorshipTotalsProvider).value;
    if (totals == null || totals.isEmpty) return const SizedBox.shrink();

    // Three separate figures rather than one sum, and that is the honest shape:
    // a one-off donation divided into a month is an invented number, and an
    // amount whose interval nobody recorded has no rhythm to normalise. Both
    // are shown only when there — usually the monthly line is the answer.
    final lines = [
      if (totals.monthlyCents > 0)
        l10n.sponsorshipsMonthlySum(
          formatAmountCents(l10n, totals.monthlyCents),
        ),
      if (totals.oneTimeCents > 0)
        l10n.sponsorshipsOneTimeSum(
          formatAmountCents(l10n, totals.oneTimeCents),
        ),
      if (totals.noIntervalCents > 0)
        l10n.sponsorshipsNoIntervalSum(
          formatAmountCents(l10n, totals.noIntervalCents),
        ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        0,
      ),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.sponsorshipsActiveCount(totals.active),
                style: theme.textTheme.titleMedium,
              ),
              if (lines.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(lines.join(' · '), style: theme.textTheme.bodyMedium),
              ],
              const SizedBox(height: AppSpacing.xs),
              // Said out loud, because every other org-wide figure in this app
              // belongs to a selected period and this one cannot: it is what is
              // being given now.
              Text(
                l10n.sponsorshipsTotalsNote,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The three questions this screen is opened with: is it running, how often is
/// it given, and who is it. The status split leads because it is the one facet
/// that changes what the list is FOR — the running patronages are the overview,
/// the ended ones are the archive somebody needs for a receipt.
class _Filters extends StatelessWidget {
  const _Filters({
    required this.controller,
    required this.query,
    required this.onSearch,
    required this.onQuery,
  });

  final TextEditingController controller;
  final SponsorshipQuery query;
  final ValueChanged<String> onSearch;
  final ValueChanged<SponsorshipQuery> onQuery;

  Future<void> _pickInterval(BuildContext context) async {
    final l10n = context.l10n;
    final picked = await showAppSheet<Object?>(
      context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final i in <SponsorshipInterval?>[
              null,
              ...SponsorshipInterval.values,
            ])
              ListTile(
                title: Text(
                  i == null
                      ? l10n.sponsorshipsFilterAll
                      : sponsorshipIntervalLabel(l10n, i),
                ),
                trailing: i == query.interval ? const Icon(Icons.check) : null,
                // Wrapped, so „Alle" is distinguishable from a dismissed
                // sheet — a bare null result cannot say which it was.
                onTap: () => Navigator.pop(sheetContext, <Object?>[i]),
              ),
          ],
        ),
      ),
    );
    if (picked is! List<Object?>) return;
    final choice = picked.first as SponsorshipInterval?;
    onQuery(
      choice == null
          ? query.copyWith(clearInterval: true)
          : query.copyWith(interval: choice),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: TextField(
            controller: controller,
            onChanged: onSearch,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: l10n.sponsorshipsSearchHint,
              isDense: true,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            spacing: AppSpacing.xs,
            children: [
              for (final (status, label) in [
                (SponsorshipStatusFilter.active, l10n.sponsorshipStatusActive),
                (SponsorshipStatusFilter.ended, l10n.sponsorshipStatusEnded),
                (SponsorshipStatusFilter.all, l10n.sponsorshipsFilterAll),
              ])
                FilterChip(
                  label: Text(label),
                  selected: query.status == status,
                  // No toggle-off: the split is a set of three and one of them
                  // is always the answer, so deselecting would leave the list
                  // describing nothing.
                  onSelected: (_) => onQuery(query.copyWith(status: status)),
                ),
              const SizedBox(width: AppSpacing.xs),
              FilterChip(
                avatar: const Icon(Icons.repeat, size: 18),
                label: Text(
                  query.interval == null
                      ? l10n.sponsorshipsFilterAnyInterval
                      : sponsorshipIntervalLabel(l10n, query.interval!),
                ),
                selected: query.interval != null,
                onSelected: (_) => _pickInterval(context),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One patronage: the SPONSOR first — this screen is about people, unlike the
/// animal detail's card, which is about one bird — then the bird and what is
/// given.
class _SponsorshipTile extends StatelessWidget {
  const _SponsorshipTile(this.row);

  final SponsorshipRow row;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final materialL10n = MaterialLocalizations.of(context);
    final s = row.sponsorship;
    final animal = row.animal;
    final active = s.isActive;

    // The bird, or the fact that there is none. An orphan keeps its row and
    // says so rather than being hidden: it is the row most likely to need
    // attention, and hiding it would leave a kept record unreachable outside
    // the Admin UI.
    final bird = animal == null
        ? l10n.sponsorshipsBirdGone
        : animalTitle(animal);
    final arrangement = [
      if (s.amountCents case final cents?) formatAmountCents(l10n, cents),
      if (s.interval case final i?) sponsorshipIntervalLabel(l10n, i),
    ].join(' ');
    String short(DateTime at) =>
        formatLocalDate(materialL10n, at, style: DateStyle.short);
    final period = switch ((s.startedAt, s.endedAt)) {
      (final from?, final to?) => '${short(from)} – ${short(to)}',
      (final from?, null) => l10n.sponsorshipSince(short(from)),
      (null, final to?) => l10n.sponsorshipUntil(short(to)),
      _ => null,
    };
    final second = [if (arrangement.isNotEmpty) arrangement, ?period].join(
      ' · ',
    );

    return ListTile(
      isThreeLine: second.isNotEmpty,
      leading: Icon(
        Icons.volunteer_activism_outlined,
        color: active ? theme.colorScheme.primary : theme.colorScheme.outline,
      ),
      title: Text(s.sponsorName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            bird,
            style: animal == null
                ? theme.textTheme.bodyMedium?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: theme.colorScheme.onSurfaceVariant,
                  )
                : null,
          ),
          if (second.isNotEmpty) Text(second),
        ],
      ),
      // Only on an ended row: the running ones are the list's default subject,
      // and a chip on every line would say nothing.
      trailing: active
          ? null
          : Chip(
              label: Text(l10n.sponsorshipStatusEnded),
              visualDensity: VisualDensity.compact,
            ),
      // The detail sheet, not the bird: the address and the mobile are what a
      // coordinator opened this screen for (a Zuwendungsbestätigung is
      // worthless without them), it is the one surface an orphan has at all,
      // and the sheet carries the way to the bird for the rows that have one.
      onTap: () => showSponsorshipDetailSheet(
        context,
        animalId: animal?.id,
        sponsorship: s,
        showAnimalLink: true,
      ),
    );
  }
}
