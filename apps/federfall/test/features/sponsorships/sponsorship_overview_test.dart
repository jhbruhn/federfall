import 'package:federfall/core/auth/current_user.dart';
import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/sponsorships/sponsorship_overview_providers.dart';
import 'package:federfall/features/sponsorships/sponsorship_overview_screen.dart';
import 'package:federfall/features/sponsorships/sponsorship_teaser_card.dart';
import 'package:federfall/l10n/l10n.dart';
import 'package:federfall_data/federfall_data.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart' hide Finder;
import 'package:mocktail/mocktail.dart';

class MockSponsorshipsRepo extends Mock implements PbSponsorshipsRepository {}

class MockAnimalsRepo extends Mock implements PbAnimalsRepository {}

const _bird = Animal(id: 'a1', species: 'Columba livia', name: 'Pip');

const _running = Sponsorship(
  id: 's1',
  animal: 'a1',
  sponsorName: 'Marlene Wolf',
  city: 'Oldenburg',
  amountCents: 1250,
  interval: SponsorshipInterval.monthly,
);

/// An ORPHAN: its bird was deleted (`sponsorships.animal` does not cascade), so
/// no keeper can reach it and it exists only on this screen.
const _orphan = Sponsorship(id: 's2', animal: '', sponsorName: 'Ada Reimer');

const _totals = SponsorshipTotals(
  total: 2,
  active: 1,
  monthlyCents: 1250,
  oneTimeCents: 5000,
);

void main() {
  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(const SponsorshipQuery());
  });

  late MockSponsorshipsRepo sponsorships;
  late MockAnimalsRepo animals;

  setUp(() {
    sponsorships = MockSponsorshipsRepo();
    animals = MockAnimalsRepo();
    when(
      () => sponsorships.browse(
        query: any(named: 'query'),
        after: any(named: 'after'),
      ),
    ).thenAnswer((_) async => const PbPage(items: [_running, _orphan]));
    when(() => animals.byIds(any())).thenAnswer((_) async => const [_bird]);
  });

  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    UserRole role = UserRole.coordinator,
    SponsorshipTotals totals = _totals,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWith(
            (ref) async =>
                AppUser(id: 'me', email: 'me@x.org', org: 'org1', role: role),
          ),
          sponsorshipsRepositoryProvider.overrideWith(
            (ref) async => sponsorships,
          ),
          animalsRepositoryProvider.overrideWith((ref) async => animals),
          // Overridden rather than mocked through the stats repository: the
          // figures are the server's, and what is under test here is what the
          // screen does with them.
          sponsorshipTotalsProvider.overrideWith((ref) async => totals),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: home,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('the patronage overview', () {
    testWidgets('names the sponsor first, with the bird beneath', (
      tester,
    ) async {
      await pump(tester, const SponsorshipOverviewScreen());

      expect(find.text('Marlene Wolf'), findsOneWidget);
      // The screen is about people, so the bird is the subtitle — resolved from
      // a second by-ids read over the page's own animal ids.
      expect(find.textContaining('Pip'), findsOneWidget);
      // The arrangement, rendered from integer cents at the edge. Matched with
      // the interval attached, because the totals card above carries 12.50 too.
      expect(find.textContaining('12.50 monthly'), findsOneWidget);
    });

    testWidgets('an orphan keeps its row and says the bird is gone', (
      tester,
    ) async {
      // The row most likely to need attention: hiding it would leave a record
      // that is KEPT on purpose (federfall-5s5j.4) unreachable outside the
      // Admin UI.
      await pump(tester, const SponsorshipOverviewScreen());

      expect(find.text('Ada Reimer'), findsOneWidget);
      expect(find.text('Bird deleted'), findsOneWidget);
    });

    testWidgets('shows the standing totals, and says they are standing', (
      tester,
    ) async {
      await pump(tester, const SponsorshipOverviewScreen());

      expect(find.text('1 running patronage'), findsOneWidget);
      expect(find.textContaining('per month'), findsOneWidget);
      // A one-off donation is reported on its own line rather than divided into
      // a month.
      expect(find.textContaining('one-off'), findsOneWidget);
      expect(
        find.text('As of now — independent of any reporting period'),
        findsOneWidget,
      );
    });

    testWidgets('a carer gets a refusal, not a heading over an empty list', (
      tester,
    ) async {
      await pump(
        tester,
        const SponsorshipOverviewScreen(),
        role: UserRole.carer,
      );

      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(find.text('Marlene Wolf'), findsNothing);
      // And it never asked the server either.
      verifyNever(
        () => sponsorships.browse(
          query: any(named: 'query'),
          after: any(named: 'after'),
        ),
      );
    });

    testWidgets('an empty DEFAULT view reads as "nothing yet"', (tester) async {
      when(
        () => sponsorships.browse(
          query: any(named: 'query'),
          after: any(named: 'after'),
        ),
      ).thenAnswer((_) async => const PbPage(items: []));

      await pump(tester, const SponsorshipOverviewScreen());

      expect(find.text('No patronages yet'), findsOneWidget);
    });

    testWidgets('an empty FILTERED view reads as "no matches"', (tester) async {
      // Which emptiness it is cannot be read off the loaded rows — the server
      // sent only what matched — so the query has to say it.
      when(
        () => sponsorships.browse(
          query: any(named: 'query'),
          after: any(named: 'after'),
        ),
      ).thenAnswer((invocation) async {
        final query =
            invocation.namedArguments[const Symbol('query')]
                as SponsorshipQuery;
        return query.status == SponsorshipStatusFilter.ended
            ? const PbPage(items: [])
            : const PbPage(items: [_running]);
      });

      await pump(tester, const SponsorshipOverviewScreen());
      expect(find.text('Marlene Wolf'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilterChip, 'Ended'));
      await tester.pumpAndSettle();

      expect(find.text('No patronage matches this selection'), findsOneWidget);
      expect(find.text('No patronages yet'), findsNothing);
    });
  });

  group('the dashboard teaser', () {
    testWidgets('gives a coordinator the count and the monthly figure', (
      tester,
    ) async {
      await pump(tester, const Scaffold(body: SponsorshipTeaserCard()));

      expect(find.text('Patronages'), findsOneWidget);
      expect(find.textContaining('1 running patronage'), findsOneWidget);
      expect(find.textContaining('12.50'), findsOneWidget);
    });

    testWidgets('renders nothing at all for a carer', (tester) async {
      // Not an empty card: a keeper reads their own residents' patronages on the
      // bird, and an org-wide figure would be a misleading fragment.
      await pump(
        tester,
        const Scaffold(body: SponsorshipTeaserCard()),
        role: UserRole.carer,
      );

      expect(find.text('Patronages'), findsNothing);
    });

    testWidgets('renders nothing when the org has no patronage at all', (
      tester,
    ) async {
      await pump(
        tester,
        const Scaffold(body: SponsorshipTeaserCard()),
        totals: const SponsorshipTotals(),
      );

      expect(find.text('Patronages'), findsNothing);
    });

    testWidgets('but stays for an org whose patronages have all ended', (
      tester,
    ) async {
      // That archive is what a Zuwendungsbestätigung is written from, and the
      // teaser is its only way in.
      await pump(
        tester,
        const Scaffold(body: SponsorshipTeaserCard()),
        totals: const SponsorshipTotals(total: 3),
      );

      expect(find.text('Patronages'), findsOneWidget);
      expect(find.textContaining('No running patronage'), findsOneWidget);
    });
  });
}
