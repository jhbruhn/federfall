import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/core/auth/roles.dart';
import 'package:federfall/features/sponsorships/sponsorship_overview_providers.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall/routing/app_routes.dart';
import 'package:federfall/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The dashboard's way into the patronage overview (federfall-ys7z): how many
/// patronages are running and what they come to per month, on the way past.
///
/// Coordinators and supervisors only, the same set as 1700000085's `COORD_SUP`
/// read branch and as the screen it opens. A keeper reads the patronages of
/// their own residents on the bird itself; an org figure would be a fragment.
///
/// Two habits copied from `_CarerWorkloadCard`, both about not moving the page:
/// it renders `SizedBox.shrink()` for every other role rather than an empty
/// card, and its loading state is `shrink()` too — the card slots into the
/// dashboard's own scroll view, so a spinner would shove the caseload around on
/// every refresh. It simply appears once loaded.
///
/// Absent, too, when the org has no patronage at all: an empty „Patenschaften"
/// card on a dashboard is chrome for a feature nobody here uses yet. An org
/// whose patronages have all ENDED still gets the card — that archive is what a
/// Zuwendungsbestätigung is written from, and it has no other way in.
class SponsorshipTeaserCard extends ConsumerWidget {
  const SponsorshipTeaserCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final role = ref.watch(currentUserProvider).value?.role;
    if (!canViewReports(role)) return const SizedBox.shrink();

    final totals = ref.watch(sponsorshipTotalsProvider).value;
    if (totals == null || totals.isEmpty) return const SizedBox.shrink();

    // The monthly figure is the one a rehab quotes. The other two sums are the
    // overview's business — a card is not the place to explain that a one-off
    // donation cannot be divided into a month.
    final monthly = totals.monthlyCents > 0
        ? l10n.sponsorshipsMonthlySum(
            formatAmountCents(l10n, totals.monthlyCents),
          )
        : null;

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: Card(
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        child: ListTile(
          leading: const IconChip(Icons.volunteer_activism_outlined),
          title: Text(
            l10n.sponsorshipsOverviewTitle,
            style: theme.textTheme.titleMedium,
          ),
          subtitle: Text(
            [l10n.sponsorshipsActiveCount(totals.active), ?monthly].join(' · '),
          ),
          trailing: const Icon(Icons.chevron_right),
          // `go`, not `push`: an imperative push would leave the address bar on
          // the dashboard while the overview is on screen.
          onTap: () => context.go(AppRoutes.sponsorships),
        ),
      ),
    );
  }
}
