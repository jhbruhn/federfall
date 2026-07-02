// Low-level helpers that translate raw PocketBase field values into the typed
// shapes the domain models use. PocketBase serialises empty relations/dates as
// the empty string and datetimes space-separated ("2026-03-10 09:00:00.000Z"),
// so every reader has to normalise those quirks in one place.

/// Parses a PocketBase datetime string into a UTC [DateTime].
///
/// Returns `null` for an absent, empty or malformed value — one garbage date
/// on one record must not make a whole list() call throw. PocketBase emits
/// datetimes space-separated rather than ISO-8601, so the space is swapped
/// for `T` before parsing.
DateTime? pbDate(Object? raw) {
  if (raw == null) return null;
  if (raw is DateTime) return raw.toUtc();
  final s = raw.toString().trim();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s.replaceFirst(' ', 'T'))?.toUtc();
}

/// Reads a non-empty string, mapping `null`/empty to `null`.
String? pbString(Object? raw) {
  if (raw == null) return null;
  final s = raw.toString();
  return s.isEmpty ? null : s;
}

/// Reads a [num] as [double], tolerating string-encoded numbers.
double? pbDouble(Object? raw) {
  if (raw == null) return null;
  if (raw is num) return raw.toDouble();
  final s = raw.toString();
  if (s.isEmpty) return null;
  return double.tryParse(s);
}

/// Reads a [num] as [int], tolerating string-encoded numbers.
int? pbInt(Object? raw) {
  if (raw == null) return null;
  if (raw is num) return raw.toInt();
  final s = raw.toString();
  if (s.isEmpty) return null;
  return int.tryParse(s);
}

/// Reads a boolean, defaulting absent/empty values to `false`.
bool pbBool(Object? raw) {
  if (raw is bool) return raw;
  if (raw is num) return raw != 0;
  return raw?.toString() == 'true';
}

/// Reads a list of strings (multi-select, file, multi-relation fields).
///
/// PocketBase returns an actual list for these, but tolerates a bare string or
/// absent value as well.
List<String> pbStringList(Object? raw) {
  if (raw == null) return const [];
  if (raw is List) {
    return raw
        .map((e) => e?.toString() ?? '')
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }
  final s = raw.toString();
  return s.isEmpty ? const [] : [s];
}

/// Resolves a PocketBase select value to its matching enum constant by wire
/// string, or `null` when absent/unknown.
T? pbEnum<T>(Iterable<T> values, String Function(T) wireOf, Object? raw) {
  if (raw == null) return null;
  final s = raw.toString();
  if (s.isEmpty) return null;
  for (final v in values) {
    if (wireOf(v) == s) return v;
  }
  return null;
}

/// Resolves a multi-select PocketBase value to a list of enum constants,
/// skipping any unknown entries.
List<T> pbEnumList<T>(
  Iterable<T> values,
  String Function(T) wireOf,
  Object? raw,
) {
  return pbStringList(raw)
      .map((s) => pbEnum(values, wireOf, s))
      .whereType<T>()
      .toList(growable: false);
}
