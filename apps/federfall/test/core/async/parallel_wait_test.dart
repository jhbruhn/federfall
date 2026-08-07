import 'dart:async';

import 'package:federfall/core/async/parallel_wait.dart';
import 'package:flutter_test/flutter_test.dart';

/// A stand-in for a repository failure. A purpose-made exception rather than a
/// `StateError`, so the test neither throws nor catches an [Error].
class _Boom implements Exception {
  const _Boom(this.what);

  final String what;

  @override
  String toString() => 'Boom: $what';
}

/// A future that fails after [ms], so completion ORDER can be controlled.
Future<T> _failsAfter<T>(int ms, _Boom error) =>
    Future.delayed(Duration(milliseconds: ms), () => throw error);

Future<T> _after<T>(int ms, T value) =>
    Future.delayed(Duration(milliseconds: ms), () => value);

void main() {
  test('returns the results in record order', () async {
    final (a, b, c) = await (
      _after(5, 1),
      _after(1, 'two'),
      _after(3, true),
    ).waitUnwrapped;

    // Positions follow the record, not the order the futures settled in.
    expect(a, 1);
    expect(b, 'two');
    expect(c, true);
  });

  test('throws the underlying error, not a ParallelWaitError', () async {
    // The whole point: `(a, b).wait` reports this as ParallelWaitError, and the
    // app's error mapping tests the concrete type — so a wrapped failure
    // renders as a generic error instead of the offline copy (federfall-s5mm).
    const failure = _Boom('server unreachable');

    await expectLater(
      (_after(1, 'ok'), _failsAfter<int>(2, failure)).waitUnwrapped,
      throwsA(same(failure)),
    );
  });

  test('waits for the slow futures before reporting a fast failure', () async {
    // `.wait` semantics, kept: an early failure must not abandon the others
    // mid-flight, or their errors land unobserved after the fact.
    var slowFinished = false;
    final slow = Future.delayed(const Duration(milliseconds: 20), () {
      slowFinished = true;
      return 1;
    });

    await expectLater(
      (_failsAfter<int>(1, const _Boom('boom')), slow).waitUnwrapped,
      throwsA(isA<_Boom>()),
    );
    expect(slowFinished, isTrue);
  });

  test('a second failure is observed, not left unhandled', () async {
    // The trap that rules out awaiting the futures one at a time: whichever
    // error is NOT rethrown still has to be handled, or it surfaces later as an
    // unhandled async error and fails the enclosing zone.
    final errors = <Object>[];

    await runZonedGuarded(
      () async {
        try {
          await (
            _failsAfter<int>(1, const _Boom('first')),
            _failsAfter<String>(5, const _Boom('second')),
          ).waitUnwrapped;
        } on _Boom {
          // Expected — the first failure, rethrown as itself.
        }
        // Long enough for an unobserved second failure to be reported.
        await Future<void>.delayed(const Duration(milliseconds: 30));
      },
      (error, _) => errors.add(error),
    );

    expect(errors, isEmpty);
  });

  test('carries the higher arities the providers actually use', () async {
    final four = await (
      _after(1, 1),
      _after(1, 2),
      _after(1, 3),
      _after(1, 4),
    ).waitUnwrapped;
    expect(four, (1, 2, 3, 4));

    final five = await (
      _after(1, 1),
      _after(1, 2),
      _after(1, 3),
      _after(1, 4),
      _after(1, 5),
    ).waitUnwrapped;
    expect(five, (1, 2, 3, 4, 5));

    final seven = await (
      _after(1, 1),
      _after(1, 2),
      _after(1, 3),
      _after(1, 4),
      _after(1, 5),
      _after(1, 6),
      _after(1, 7),
    ).waitUnwrapped;
    expect(seven, (1, 2, 3, 4, 5, 6, 7));
  });
}
