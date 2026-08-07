import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Strips `//` line comments and `///` doc comments, so the rule is applied to
/// code and not to the several places that legitimately *discuss* `.wait`.
String _code(String source) => source
    .split('\n')
    .where((line) => !line.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  test('no provider gathers with the record .wait (federfall-s5mm)', () {
    // `(a, b, …).wait` reports ANY failure as a ParallelWaitError, and this
    // app's error mapping tests for a RepositoryException — so a dropped
    // connection renders as a generic error AND discards the content already on
    // screen, instead of the offline copy AsyncValueView is built to keep.
    // `core/async/parallel_wait.dart` provides `waitUnwrapped` for records and
    // `Future.wait` covers a homogeneous list; neither wraps.
    //
    // A source sweep rather than a test per call site: the failure mode is
    // invisible until someone is offline, and a new provider written next month
    // would reintroduce it silently. `test_rules.py`'s guest sweep guards its
    // access rules the same way.
    final offenders = <String>[];
    final lib = Directory('lib');

    for (final entity in lib.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      // Generated code is rewritten by build_runner, not by hand.
      if (entity.path.endsWith('.g.dart') ||
          entity.path.endsWith('.freezed.dart')) {
        continue;
      }
      final lines = _code(entity.readAsStringSync()).split('\n');
      for (var i = 0; i < lines.length; i++) {
        // The record form always closes its parenthesised record immediately
        // before `.wait` — `Future.wait(...)` is a call and never matches.
        if (RegExp(r'\)\s*\.wait\b').hasMatch(lines[i])) {
          offenders.add('${entity.path}:${i + 1}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Use `.waitUnwrapped` (core/async/parallel_wait.dart) so the error '
          'the UI receives is the one that actually happened:\n'
          '${offenders.join('\n')}',
    );
  });
}
