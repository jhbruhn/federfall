import 'package:federfall_data/src/pb_repository.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:meta/meta.dart';
import 'package:pocketbase/pocketbase.dart';

/// Which patronages the overview is asking for (federfall-ys7z).
///
/// An `ended_at`-based split, stated as an explicit set the way the case
/// browser's "active" facet names its statuses: the boundary is the same one
/// `SponsorshipState.isActive` applies on the record, so a keeper's card and
/// this list cannot disagree about which rows they mean.
enum SponsorshipStatusFilter {
  /// Still running: no end date, or one still in the future.
  active,

  /// Over: an end date that has passed.
  ended,

  /// Both — including the rows no keeper can reach (a bird that has left
  /// aviary care, or an orphan whose bird was deleted).
  all,
}

/// What the patronage overview is looking for.
///
/// Every field narrows; the default is the running patronages, which is the
/// question the screen exists to answer. Turned into a bound filter by
/// [PbSponsorshipsRepository.filterFor], so nothing here is ever interpolated
/// into a filter string.
@immutable
class SponsorshipQuery {
  const SponsorshipQuery({
    this.status = SponsorshipStatusFilter.active,
    this.interval,
    this.text = '',
  });

  final SponsorshipStatusFilter status;

  /// Exactly this rhythm, or null for any. A row with no interval recorded is
  /// matched by none of them, which is correct: it has no rhythm.
  final SponsorshipInterval? interval;

  /// Free text matched against the sponsor's name and their city.
  ///
  /// Those two and nothing else on purpose: a substring search over an address
  /// or a mobile number is not a question anybody asks of this screen, and
  /// widening it would put more PII into the shape of a query.
  final String text;

  /// Whether anything narrows the DEFAULT view (the running patronages), which
  /// is what tells "nothing yet" from "no matches" — the same stance the case
  /// browser takes, where the default view's emptiness reads as "nothing yet".
  bool get isNarrowed =>
      status != SponsorshipStatusFilter.active ||
      interval != null ||
      text.trim().isNotEmpty;

  SponsorshipQuery copyWith({
    SponsorshipStatusFilter? status,
    SponsorshipInterval? interval,
    String? text,
    bool clearInterval = false,
  }) => SponsorshipQuery(
    status: status ?? this.status,
    interval: clearInterval ? null : (interval ?? this.interval),
    text: text ?? this.text,
  );

  @override
  bool operator ==(Object other) =>
      other is SponsorshipQuery &&
      other.status == status &&
      other.interval == interval &&
      other.text == text;

  @override
  int get hashCode => Object.hash(status, interval, text);
}

/// Repository over the `sponsorships` collection — Patenschaften on aviary
/// residents (federfall-5s5j).
///
/// Every read here is already narrowed by the server: the access rule resolves
/// through `animal.current_aviary.keeper`, so a keeper sees the patronages of
/// their own residents and a coordinator/supervisor sees the org's. Nothing in
/// this class filters by viewer, and nothing should — a client-side scope over
/// PII would be a second, weaker copy of the boundary.
class PbSponsorshipsRepository extends PbRepository<Sponsorship> {
  PbSponsorshipsRepository(PocketBase pb)
    : super(
        pb: pb,
        collection: 'sponsorships',
        fromRecord: Sponsorship.fromRecord,
      );

  /// Every patronage recorded for an animal, newest arrangement first.
  ///
  /// Sorted by `-started_at` with `-created` behind it, because `started_at`
  /// is optional: rows without one would otherwise land in an arbitrary order
  /// among themselves.
  Future<List<Sponsorship>> forAnimal(String animalId) => list(
    filter: filterExpr('animal = {:a}', {'a': animalId}),
    sort: '-started_at,-created',
  );

  /// One page of the org's patronages matching [query], by sponsor name
  /// (federfall-ys7z).
  ///
  /// Server-side filtered and cursor-paged, per federfall-trep: this list grows
  /// with the org and must not be read whole to narrow it on the device — the
  /// more so here, where every row is a private person's contact details.
  ///
  /// Ordered by `sponsor_name` because the screen is about PEOPLE and gets
  /// looked up by name. That order is SQLite's BINARY collation, so it is
  /// case-sensitive in the way the animals registry's `+name` order is; rows
  /// with the same name are separated by the id the cursor also carries.
  Future<PbPage<Sponsorship>> browse({
    SponsorshipQuery query = const SponsorshipQuery(),
    PbCursor? after,
    int perPage = 50,
    DateTime? now,
  }) => page(
    filter: filterFor(query, now: now),
    after: after,
    perPage: perPage,
    sortKey: const PbSortKey('sponsor_name', descending: false),
  );

  /// How many patronages the animal carries.
  ///
  /// This is what the disposition sheet's transfer warning counts — a COUNT, so
  /// the sentence can say how much data is about to change hands without naming
  /// a single sponsor.
  Future<int> countForAnimal(String animalId) =>
      count(filter: filterExpr('animal = {:a}', {'a': animalId}));

  /// The bound filter for [query], or null when it narrows nothing at all.
  ///
  /// [now] is the instant the active/ended split is resolved against
  /// (defaults to this moment, in UTC — every PocketBase timestamp is UTC).
  /// Exposed so a test can pin it: „läuft bis Dezember" has to come back as
  /// running, and a suite that asked the wall clock could not say so twice.
  PbFilter? filterFor(SponsorshipQuery query, {DateTime? now}) {
    final clauses = <String>[];
    final params = <String, dynamic>{};

    // An empty `ended_at` is how PocketBase stores an unset date, and a date in
    // the future is still running — the same two-part answer
    // `SponsorshipState.isActive` gives. Stated as a set rather than as a
    // negation so the two halves cannot drift into overlapping or leaving a
    // gap: every row is in exactly one of them.
    final at = (now ?? DateTime.now()).toUtc();
    switch (query.status) {
      case SponsorshipStatusFilter.active:
        clauses.add('(ended_at = "" || ended_at > {:now})');
        params['now'] = at;
      case SponsorshipStatusFilter.ended:
        clauses.add('(ended_at != "" && ended_at <= {:now})');
        params['now'] = at;
      case SponsorshipStatusFilter.all:
        break;
    }

    if (query.interval case final interval?) {
      clauses.add('interval = {:i}');
      params['i'] = interval.wire;
    }

    final text = query.text.trim();
    if (text.isNotEmpty) {
      clauses.add('(sponsor_name ~ {:q} || city ~ {:q})');
      params['q'] = text;
    }

    if (clauses.isEmpty) return null;
    return filterExpr(clauses.join(' && '), params);
  }
}
