import 'package:federfall/data/repository_providers.dart';
import 'package:federfall/features/cases/cases_providers.dart';
import 'package:federfall_models/federfall_models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'eggs_providers.g.dart';

/// The gap that separates two clutches (federfall-4agw). A pigeon lays its two
/// eggs roughly 44 h apart and starts the next clutch weeks later, so anything
/// beyond this is a new clutch. A documented constant rather than an org
/// setting: it is avian biology, not a house rule.
const int kClutchGapDays = 5;

/// Every laying event recorded for an animal, oldest first — the lifetime
/// ledger behind the animal detail's egg section, its per-month chart and
/// clutch grouping.
@riverpod
Future<List<EggRecord>> eggsForAnimal(Ref ref, String animalId) async {
  final repo = await ref.watch(eggRecordsRepositoryProvider.future);
  return repo.forAnimal(animalId);
}

/// The laying events that fall inside a case's own window, newest first — the
/// case timeline source, served off the [caseBundle] so the case detail needs
/// no extra request.
///
/// Deliberately narrower than `markingsForCase`, which shows the animal's whole
/// lifetime on every case timeline: a ring is a standing property of the bird,
/// an egg is a dated event, and a lifetime of them would swamp the chronology
/// of one treatment episode.
@riverpod
Future<List<EggRecord>> eggsForCase(Ref ref, String caseId) async {
  final bundle = await ref.watch(caseBundleProvider(caseId).future);
  final eggs = await caseBundleList(ref, caseId, (b) => b.eggs, () async {
    final repo = await ref.watch(eggRecordsRepositoryProvider.future);
    return repo.forAnimal(bundle.medicalCase.animal);
  });
  return eggsInCaseWindow(eggs, bundle);
}

/// Narrows a lifetime of laying events to the ones belonging to [bundle]'s
/// case: from its admission (unbounded before it if none is recorded) to its
/// latest disposition, or to now while the case is still open.
List<EggRecord> eggsInCaseWindow(List<EggRecord> eggs, CaseBundle bundle) {
  final from = bundle.medicalCase.admittedAt;
  // dispositions come newest-first out of the bundle.
  final closed = bundle.dispositions
      .map((d) => d.disposedAt ?? d.created)
      .nonNulls
      .firstOrNull;
  final until = closed ?? DateTime.now();
  return eggs.where((e) {
    final at = e.laidAt ?? e.created;
    if (at == null) return false;
    if (from != null && at.isBefore(from)) return false;
    return !at.isAfter(until);
  }).toList();
}

/// Splits an ascending list of laying events into clutches: a gap longer than
/// [kClutchGapDays] between consecutive events starts a new one. Derived from
/// the dates every time — a clutch is never stored, so it cannot go stale when
/// a record is edited or reassigned.
List<List<EggRecord>> groupIntoClutches(List<EggRecord> eggs) {
  final ascending = [...eggs]
    ..sort((a, b) {
      final at = a.laidAt ?? a.created ?? _epoch;
      final bt = b.laidAt ?? b.created ?? _epoch;
      return at.compareTo(bt);
    });

  final clutches = <List<EggRecord>>[];
  DateTime? previous;
  for (final egg in ascending) {
    final at = egg.laidAt ?? egg.created ?? _epoch;
    // Compared as a duration, not in whole days: `inDays` truncates, so a
    // 5-and-a-half-day gap would read as 5 and merge two clutches.
    if (previous == null ||
        at.difference(previous) > const Duration(days: kClutchGapDays)) {
      clutches.add([egg]);
    } else {
      clutches.last.add(egg);
    }
    previous = at;
  }
  return clutches;
}

/// The clutch a single record belongs to, derived from the animal's whole
/// ledger — the scope choice the reassignment sheet offers ("this egg" vs "the
/// whole clutch").
List<EggRecord> clutchContaining(List<EggRecord> eggs, EggRecord egg) =>
    groupIntoClutches(eggs).firstWhere(
      (clutch) => clutch.any((e) => e.id == egg.id),
      orElse: () => [egg],
    );

/// The headline numbers for an animal's laying history. Confirmed and presumed
/// eggs are counted together but [presumedEggs] stays separate, so a guess is
/// always visible as one instead of hardening into a fact.
class EggLayingSummary {
  const EggLayingSummary({
    required this.totalEggs,
    required this.eggsLast12Months,
    required this.presumedEggs,
    required this.lastLaidAt,
  });

  /// Built from an animal's full ledger. Counts SUM `count`, not rows — one row
  /// can record a two-egg clutch whose exact dates were unknown.
  factory EggLayingSummary.from(List<EggRecord> eggs, {DateTime? now}) {
    final cutoff = (now ?? DateTime.now()).subtract(const Duration(days: 365));
    var total = 0;
    var recent = 0;
    var presumed = 0;
    DateTime? last;
    for (final egg in eggs) {
      total += egg.count;
      if (egg.attribution == EggAttribution.presumed) presumed += egg.count;
      final at = egg.laidAt ?? egg.created;
      if (at != null) {
        if (at.isAfter(cutoff)) recent += egg.count;
        if (last == null || at.isAfter(last)) last = at;
      }
    }
    return EggLayingSummary(
      totalEggs: total,
      eggsLast12Months: recent,
      presumedEggs: presumed,
      lastLaidAt: last,
    );
  }

  final int totalEggs;
  final int eggsLast12Months;

  /// Eggs whose layer is only presumed — surfaced next to the totals rather
  /// than hidden from them.
  final int presumedEggs;
  final DateTime? lastLaidAt;

  bool get isEmpty => totalEggs == 0;
}

final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(0);
