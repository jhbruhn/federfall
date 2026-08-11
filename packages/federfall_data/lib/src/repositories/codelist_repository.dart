import 'package:federfall_data/src/pb_repository.dart';

/// Labels an org gives a catch-all entry, lower-cased (federfall-do0l).
///
/// Matched WHOLE, not as a prefix: "Sonstiges" is a catch-all, "Sonstige
/// Verletzung" is a diagnosis like any other and keeps its alphabetical place.
const _catchAllLabels = <String>{
  'sonstiges',
  'sonstige',
  'sonstiger',
  'andere',
  'anderes',
  'other',
  'others',
  'misc',
  'miscellaneous',
  'unbekannt',
  'unknown',
};

/// True when [label] names a catch-all — the entry a reader picks once nothing
/// else on the list fits.
bool isCatchAllLabel(String label) =>
    _catchAllLabels.contains(label.trim().toLowerCase());

/// Moves the catch-all entries of an already-ordered code list to the end,
/// leaving every other entry exactly where it was.
///
/// A partition rather than a `sort`: the incoming order is the server's, and
/// `List.sort` is not stable, so comparing would be free to shuffle entries
/// this has no opinion about. Two catch-alls keep their relative order.
List<T> catchAllLast<T>(List<T> entries, String Function(T) label) {
  final rest = <T>[];
  final catchAll = <T>[];
  for (final e in entries) {
    (isCatchAllLabel(label(e)) ? catchAll : rest).add(e);
  }
  return List<T>.unmodifiable([...rest, ...catchAll]);
}

/// The shared reads of a supervisor-managed `{label, active}` code list.
///
/// Both return **picker order**: label-sorted by the server, then catch-alls
/// appended. That order is defined once here because it is a display rule no
/// call site can be trusted to remember — sorting alphabetically is what put
/// *Sonstiges* between *Krankheit* and *Trauma*, where a reader scanning for
/// their case stops at "Other" and assumes the list ended (federfall-do0l).
///
/// It reads the label rather than a stored rank, so an org whose catch-all is
/// worded differently — or renamed after the fact — falls back to alphabetical
/// and lands in the middle again. An explicit `sort_order` column is the fix
/// that would not; this is the cheap one.
mixin CodelistRepository<T> on PbRepository<T> {
  /// The entry's display label, i.e. the column this list sorts by.
  String labelOf(T entry);

  /// The FULL list, inactive entries included — what a picker needs to resolve
  /// a stored id whose entry has since been retired, and what the code-list
  /// editor shows.
  Future<List<T>> codelist() async =>
      catchAllLast(await list(sort: 'label'), labelOf);

  /// Active entries only, for a picker offering the current vocabulary.
  Future<List<T>> active() async => catchAllLast(
    await list(filter: filterExpr('active = true'), sort: 'label'),
    labelOf,
  );
}
