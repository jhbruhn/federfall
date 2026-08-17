import 'dart:io';

import 'package:federfall/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Strips `//` line and `///` doc comments, so the sweeps below apply to code
/// and not to the places that legitimately *discuss* the banned spellings.
String _code(String source) => source
    .split('\n')
    .where((line) => !line.trimLeft().startsWith('//'))
    .join('\n');

/// Every hand-written `.dart` file under `lib/`, minus the one file that is
/// allowed to format a date and the generated trees nobody edits.
Iterable<File> _appSources() sync* {
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    if (entity.path.endsWith('.g.dart') ||
        entity.path.endsWith('.freezed.dart') ||
        entity.path.startsWith('lib/l10n/gen/') ||
        entity.path == 'lib/ui/widgets/date_field.dart') {
      continue;
    }
    yield entity;
  }
}

void main() {
  // Resolve the real MaterialLocalizations for a known locale so the formatted
  // strings are deterministic.
  late MaterialLocalizations m;

  setUp(() async {
    m = await GlobalMaterialLocalizations.delegate.load(const Locale('en'));
  });

  group('formatLocalDate', () {
    test('returns empty string for null', () {
      expect(formatLocalDate(m, null), '');
    });

    test('converts a UTC timestamp to local time before formatting', () {
      // PocketBase stores UTC; the displayed date must be the local one.
      final utc = DateTime.utc(2026, 3, 4, 9, 30);
      final local = utc.toLocal();

      expect(formatLocalDate(m, utc), m.formatMediumDate(local));
      expect(
        formatLocalDate(m, utc, withTime: true),
        '${m.formatMediumDate(local)}, '
        '${m.formatTimeOfDay(TimeOfDay.fromDateTime(local))}',
      );
    });

    test('leaves an already-local value alone', () {
      // `toLocal()` is idempotent, which is what lets form state and picker
      // results share one formatter with the server's UTC timestamps.
      final local = DateTime(2026, 3, 4, 9, 30);
      expect(formatLocalDate(m, local), m.formatMediumDate(local));
    });

    test('the short style is numeric and carries the year', () {
      final utc = DateTime.utc(2026, 6, 2, 9, 30);
      expect(
        formatLocalDate(m, utc, style: DateStyle.short),
        m.formatShortDate(utc.toLocal()),
      );
      // The distinction the clutch header depends on: medium has no year.
      expect(m.formatShortDate(utc.toLocal()), contains('2026'));
      expect(m.formatMediumDate(utc.toLocal()), isNot(contains('2026')));
    });

    test('the compact style is all-numeric, for a chart axis', () async {
      final utc = DateTime.utc(2026, 6, 2, 9, 30);
      expect(
        formatLocalDate(m, utc, style: DateStyle.compact),
        m.formatCompactDate(utc.toLocal()),
      );
      // Why it exists: German spells the month out in the short form, which is
      // twice the width a chart axis has for a label (federfall-yapf).
      final de = await GlobalMaterialLocalizations.delegate.load(
        const Locale('de'),
      );
      expect(de.formatShortDate(utc.toLocal()), contains('Juni'));
      expect(de.formatCompactDate(utc.toLocal()), isNot(contains('Juni')));
    });
  });

  // Two source sweeps rather than a test per screen. The defect is invisible on
  // a UTC-clocked machine and reaches real users only as an off-by-one day near
  // midnight, so a screen written next month would reintroduce it in silence
  // (federfall-yok0 collected nine of them). `no_record_wait_test.dart` guards
  // its own invariant the same way.
  group('nothing but date_field.dart formats a date (federfall-yok0)', () {
    test('no screen calls a MaterialLocalizations date formatter', () {
      final offenders = <String>[];
      final banned = RegExp(
        r'\.format(Medium|Short|Full|Compact)Date\b|\.formatTimeOfDay\b',
      );

      for (final file in _appSources()) {
        final lines = _code(file.readAsStringSync()).split('\n');
        for (var i = 0; i < lines.length; i++) {
          if (banned.hasMatch(lines[i])) offenders.add('${file.path}:${i + 1}');
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'MaterialLocalizations formats the fields it is handed and does '
            'NOT convert time zones, so calling it on a PocketBase timestamp '
            'renders the UTC calendar day. Use `formatLocalDate` '
            '(ui/widgets/date_field.dart):\n${offenders.join('\n')}',
      );
    });

    test('every intl DateFormat formats a local value', () {
      final offenders = <String>[];

      for (final file in _appSources()) {
        // Split on `;`, not on newlines: these calls chain across several lines
        // (`DateFormat.yMd(\n  locale,\n).add_Hm().format(x.toLocal())`).
        for (final statement in _code(file.readAsStringSync()).split(';')) {
          if (!statement.contains('DateFormat')) continue;
          if (!statement.contains('.format(')) continue;
          // A `DateTime(...)` built right there is local by construction — the
          // month-name lookups in the charts format `DateTime(2000, month)`.
          if (statement.contains('DateTime(')) continue;
          if (statement.contains('toLocal()')) continue;
          offenders.add('${file.path}: ${statement.trim()}');
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'An intl DateFormat formats the fields it is handed too. Add '
            '`.toLocal()` — a no-op on a value that is already local, so it is '
            'never the wrong call:\n${offenders.join('\n')}',
      );
    });
  });
}
