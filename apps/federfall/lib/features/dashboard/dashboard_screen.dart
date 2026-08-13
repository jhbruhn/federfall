import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/auth/roles.dart';
import 'package:federfall/core/error/error_message.dart';
import 'package:federfall/core/realtime/live_refresh.dart';
import 'package:federfall/features/cases/cases_browser.dart';
import 'package:federfall/features/cases/cases_labels.dart';
import 'package:federfall/features/cases/medications/batch_administration_sheet.dart';
import 'package:federfall/features/cases/pending_case_query.dart';
import 'package:federfall/features/cases/placements/placements_providers.dart';
import 'package:federfall/features/dashboard/dashboard_providers.dart';
import 'package:federfall/features/home/account_menu.dart';
import 'package:federfall/features/sponsorships/sponsorship_teaser_card.dart';
import 'package:federfall/features/worklist/worklist.dart';
import 'package:federfall/features/worklist/worklist_providers.dart';
import 'package:federfall/features/worklist/worklist_tile.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/routing/app_routes.dart';
import 'package:federfall/ui/ui.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Dashboard tab of the navigation shell (FED-7.1): the carer's Today preview
/// plus a caseload KPI grid. Each tile taps through to the pre-filtered case
/// browser — or the aviaries list (ctw.6). Scope follows the access rules via
/// [dashboardSummaryProvider].
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    // Live-sync the caseload KPIs as cases are admitted / dispositioned.
    // A carer's KPIs include cases shared *with* them, so watch 'case_shares'
    // too — a share grants/revokes visibility without changing the case record.
    // The carer workload card rides along: it watches this summary, so
    // invalidating it rebuilds the card — and that re-reads the roster too, so
    // a handoff moves a case between rows without a second subscription.
    // (A pure role/activation change lands on the next refresh; nothing here
    // subscribes to 'users'.)
    ref.liveRefresh(
      const ['cases', 'dispositions', 'case_shares'],
      () => ref.invalidate(dashboardSummaryProvider),
    );
    final summary = ref.watch(dashboardSummaryProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.dashboardTitle),
        actions: const [AccountMenu()],
      ),
      body: AsyncValueView<DashboardSummary>(
        value: summary,
        onRetry: () => ref.invalidate(dashboardSummaryProvider),
        data: (s) {
          final caseload = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.dashboardCaseloadTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              _KpiGrid(s),
            ],
          );

          return RefreshIndicator(
            onRefresh: () => ref.refresh(dashboardSummaryProvider.future),
            // Keyed on the width actually available, not on the window class:
            // a NavigationRail stands beside this body on medium and expanded
            // windows, so `context.isExpanded` promised a split the content
            // never had room for (federfall-773v). Same mechanism the
            // statistics screen uses.
            child: LayoutBuilder(
              builder: (context, constraints) {
                final twoColumn =
                    constraints.maxWidth >= kDashboardTwoColumnMin;
                // Wide windows place the actionable Today preview and the
                // caseload overview side by side (federfall-zbe); narrower
                // ones stack them. The workload card follows the caseload in
                // both — it is reference material for the oversight roles, not
                // an action list. Today always leads: first column when there
                // are two, first card when there is one, and even with nothing
                // due it shows a compact "all caught up" card so the
                // actionable section is the consistent lead (federfall-6ds).
                final body = twoColumn
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // showEmptyState so the column is never blank beside
                          // the caseload when nothing is due.
                          const Expanded(
                            child: _WorklistPreview(showEmptyState: true),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                caseload,
                                const _CarerWorkloadCard(),
                                const SponsorshipTeaserCard(),
                              ],
                            ),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _WorklistPreview(showEmptyState: true),
                          caseload,
                          const _CarerWorkloadCard(),
                          const SponsorshipTeaserCard(),
                        ],
                      );

                return ContentBounds(
                  maxWidth: twoColumn ? kWideContentMaxWidth : kContentMaxWidth,
                  child: ListView(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    children: [body],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// Compact "Today" card at the top of the dashboard: the first few worklist
/// items with a link to the full screen. Renders nothing when nothing is due
/// (so it never adds empty chrome) — unless [showEmptyState], used by the wide
/// two-column layout where a blank column would look broken; there it shows a
/// small "all caught up" card instead.
class _WorklistPreview extends ConsumerWidget {
  const _WorklistPreview({this.showEmptyState = false});

  final bool showEmptyState;

  static const _previewMax = 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    // Live-sync the preview too (else it only updated on the Today tab), plus
    // the 1-minute tick for time-relative items.
    ref
      ..liveRefresh(
        worklistLiveCollections,
        () => ref.invalidate(worklistSourceProvider),
      )
      ..watch(worklistTickerProvider);

    final async = ref.watch(worklistProvider);
    // Whatever is already on screen STAYS on screen through a reload
    // (federfall-f8xe). The ticker invalidates this every minute and refetches
    // it every 15, so a card that renders `SizedBox.shrink()` for anything but
    // `data` blinks out on a cadence — for the length of a round trip on the
    // refetch, and a failed one used to hide it until the next tick. The Today
    // tab never had that because it goes through `AsyncValueView`, whose
    // `skipLoadingOnReload` the ticker's own doc already claims for both.
    final items = async.value;
    final error = async.hasError ? async.error : null;
    // A dropped connection while a list is already up defers to the app-wide
    // offline strip rather than replacing good data with an error — the same
    // trade `AsyncValueView` makes, via the same predicate.
    final showError =
        error != null && !(items != null && isNetworkError(error));
    final due = items ?? const <WorklistItem>[];
    // The headline counts obligations, not rows: a quiet case is worth
    // surfacing but nobody owes it anything today (federfall-9m9n).
    //
    // The same split orders the preview. The worklist is sorted soonest-due
    // first, and a case that has been quiet for 39 days carries a `dueAt` 39
    // days old — so under a plain date sort the quiet cases took the whole
    // preview and a dose due this afternoon fell off the end of it. Within
    // each half the date order stands.
    final actionable = due.where((i) => i.kind.isDue).toList();
    final quiet = due.where((i) => !i.kind.isDue).toList();
    final preview = [...actionable, ...quiet];
    final dueCount = actionable.length;
    final quietCount = quiet.length;

    // The narrow layout adds no chrome when nothing is due, so it must not pop
    // a card in while the first load is still in flight either.
    if (!showEmptyState && due.isEmpty && !showError) {
      return const SizedBox.shrink();
    }

    final now = DateTime.now();
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        children: [
          // A refresh says so instead of vanishing. The 2px slot is always
          // present, so appearing and disappearing cannot shift the card's
          // contents by a hair.
          SizedBox(
            height: 2,
            child: async.isLoading
                ? const LinearProgressIndicator(minHeight: 2)
                : null,
          ),
          ListTile(
            leading: IconChip(
              showError
                  ? Icons.error_outline
                  : due.isEmpty
                  ? Icons.check_circle_outline
                  : Icons.today_outlined,
            ),
            title: Text(l10n.todayTitle, style: theme.textTheme.titleMedium),
            subtitle: switch ((showError, items)) {
              (true, _) => Text(loadErrorMessage(l10n, error!)),
              // Before the first load lands there is nothing true to say; the
              // progress bar above is the whole message.
              (_, null) => null,
              _ when due.isEmpty => Text(l10n.worklistEmpty),
              _ => Text(
                [
                  if (dueCount > 0) l10n.worklistDueCount(dueCount),
                  if (quietCount > 0) l10n.worklistQuietCount(quietCount),
                ].join(' · '),
              ),
            },
            trailing: showError
                ? TextButton(
                    onPressed: () => ref.invalidate(worklistSourceProvider),
                    child: Text(l10n.actionRetry),
                  )
                : due.isEmpty
                ? null
                : TextButton(
                    // `go`, not `push`: an imperative push leaves the address
                    // bar on the dashboard while Today is on screen.
                    onPressed: () => context.go(AppRoutes.today),
                    child: Text(l10n.worklistSeeAll),
                  ),
          ),
          if (!showError) ...[
            // A dose round belongs where the work is first seen, not only on
            // Today (federfall-o3gz): the whole point is that giving nine birds
            // the same drug is one act, and making the carer navigate first is
            // the step that costs. Only rounds appear here — one drug with a
            // single due is already a row below with its own log-dose button.
            //
            // Deliberately uncapped, unlike the rows: a round is a DRUG, not a
            // bird, so the list is short by construction, and hiding one would
            // hide the act rather than shorten a list.
            for (final round in groupMedicationDuesByDrug(actionable))
              if (round.isRound) _DoseRoundRow(round: round),
            for (final item in preview.take(_previewMax))
              WorklistTile(item: item, now: now),
            if (due.isNotEmpty) const SizedBox(height: AppSpacing.xs),
          ],
        ],
      ),
    );
  }
}

/// One drug due on several birds, offered as a single round straight from the
/// dashboard (federfall-o3gz).
///
/// Emphasised rather than styled like a due row, because it is an ACTION and
/// the rows around it are a list. It counts the givable dues, not the group —
/// a due whose prescription did not come along cannot be given from here and
/// must not be promised.
class _DoseRoundRow extends ConsumerWidget {
  const _DoseRoundRow({required this.round});

  final MedicationDueGroup round;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return ListTile(
      leading: const IconChip(Icons.vaccines_outlined),
      title: Text(
        l10n.doseRoundHeading(round.drug, round.givable.length),
        style: theme.textTheme.titleSmall,
      ),
      trailing: TextButton(
        onPressed: () async {
          final saved = await showBatchAdministrationSheet(
            context,
            group: round,
          );
          if (saved == null) return;
          ref.invalidate(worklistSourceProvider);
        },
        child: Text(l10n.doseRoundAction),
      ),
    );
  }
}

/// Who is carrying how much (federfall-9mit): every team member with their open
/// caseload, busiest first, each row tapping through to that carer's open cases
/// in the Cases tab.
///
/// Coordinators and supervisors only — they read org-wide, so the figures are
/// the whole picture; a carer sees their own cases plus what was shared with
/// them, which would make the same card a misleading fragment. Renders nothing
/// for every other role (the server rules stay the real boundary).
class _CarerWorkloadCard extends ConsumerWidget {
  const _CarerWorkloadCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final role = ref.watch(currentUserProvider).value?.role;
    if (!canViewReports(role)) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: AsyncValueView<List<CarerWorkload>>(
        value: ref.watch(carerWorkloadProvider),
        onRetry: () => ref.invalidate(carerWorkloadProvider),
        // The card slots into the dashboard's own scroll view, so a spinner
        // here would push the caseload around on every refresh; it simply
        // appears once loaded.
        loading: const SizedBox.shrink(),
        data: (rows) {
          // A row saying somebody carries nothing is not workload, and there
          // are usually several — they made the card longer than the fact it
          // reports (federfall-06v1). They collapse into one line instead of
          // vanishing: "who is on the team" is still worth knowing, it just
          // isn't worth a row each. Filtered on the COUNT, not on activity —
          // a deactivated member holding open cases is precisely the row that
          // needs acting on.
          final carrying = rows.where((r) => r.openCases > 0).toList();
          final idle = rows.length - carrying.length;
          return BreakdownCard(
            title: l10n.dashboardWorkloadTitle,
            // With nobody carrying anything, the idle count IS the answer —
            // the stock empty message would claim there is no team at all.
            emptyMessage: idle > 0
                ? l10n.dashboardWorkloadIdle(idle)
                : l10n.dashboardWorkloadEmpty,
            footnote: idle > 0 ? l10n.dashboardWorkloadIdle(idle) : null,
            rows: [
              for (final row in carrying)
                BreakdownRow(
                  memberLabel(row.user),
                  row.openCases,
                  subtitle: _subtitle(l10n, row.user),
                  // Open cases, so the target keeps the browser's "active"
                  // default — the list then holds exactly the number tapped.
                  onTap: () => showCasesFiltered(
                    context,
                    ref,
                    CaseQuery(carer: row.user.id),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// The member's role, plus an "inactive" note when they are deactivated —
  /// a deactivated member with open cases is the row that needs acting on, and
  /// without the note their presence in a workload list looks like a bug.
  static String? _subtitle(AppLocalizations l10n, AppUser user) {
    final role = user.role;
    final parts = [
      if (role != null) userRoleLabel(l10n, role),
      if (!user.isActive) l10n.memberInactive,
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

/// The caseload KPI grid: a 2-column grid of tappable metric tiles. Each case
/// tile jumps to the Cases tab with its filter applied; the aviary tile
/// switches to the Aviaries tab.
class _KpiGrid extends ConsumerWidget {
  const _KpiGrid(this.summary);

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final year = DateTime.now().year;
    final ready = summary.byStatus[CaseStatus.readyForRelease] ?? 0;

    return KpiGrid([
      KpiCard(
        icon: Icons.medical_information_outlined,
        label: l10n.dashboardActiveCases,
        value: '${summary.activeCount}',
        onTap: () =>
            showCasesFiltered(context, ref, const CaseQuery(allScope: true)),
      ),
      KpiCard(
        icon: Icons.input_outlined,
        label: l10n.dashboardIntakesThisYear,
        value: '${summary.intakesThisYear}',
        onTap: () => showCasesFiltered(
          context,
          ref,
          CaseQuery(
            allScope: true,
            activity: CaseActivity.all,
            admittedRange: DateTimeRange(
              start: DateTime(year),
              end: DateTime(year, 12, 31),
            ),
          ),
        ),
      ),
      KpiCard(
        icon: Icons.task_alt_outlined,
        label: caseStatusLabel(l10n, CaseStatus.readyForRelease),
        value: '$ready',
        onTap: () => showCasesFiltered(
          context,
          ref,
          const CaseQuery(
            allScope: true,
            status: CaseStatus.readyForRelease,
          ),
        ),
      ),
      // The aviary tile switches to the Aviaries tab rather than filtering the
      // case list.
      KpiCard(
        icon: Icons.holiday_village_outlined,
        label: l10n.dashboardInAviary,
        value: '${summary.inAviaryCount}',
        onTap: () => context.go(AppRoutes.aviaries),
      ),
    ]);
  }
}
