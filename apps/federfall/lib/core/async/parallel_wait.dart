/// `(a, b, …).wait` for futures whose failure reaches the UI.
///
/// `dart:async`'s record `.wait` reports ANY failure as a [ParallelWaitError],
/// never as the error that actually occurred. This app's error mapping reads
/// the concrete type — `isNetworkError` and `loadErrorMessage` both test for a
/// `RepositoryException` — so a wrapped failure renders as a generic "something
/// went wrong" AND takes the content already on screen with it, where
/// `AsyncValueView` would otherwise keep it until the connection returns. On a
/// case list that costs the user their scroll position and their filters, for a
/// condition they can only wait out (federfall-s5mm).
///
/// `waitUnwrapped` waits exactly as `.wait` does — every future is observed, so
/// none of their errors is left unhandled — and then throws the FIRST failure
/// as itself.
///
/// Prefer it over awaiting the futures one at a time when the calls are real
/// round trips. Starting a second future and awaiting it *after* the first
/// leaves its failure unobserved for as long as the first is in flight, so if
/// the first throws, the second surfaces as an unhandled async error instead.
/// Awaiting in sequence is only free when the futures are already resolved or
/// share one cached dependency.
library;

import 'dart:async';

Future<List<Object?>> _waitAll(List<Future<Object?>> futures) =>
    Future.wait<Object?>(futures);

/// Adds [waitUnwrapped] to a pair of futures.
extension FutureRecord2<A, B> on (Future<A>, Future<B>) {
  /// Both results, or the first failure thrown as itself.
  Future<(A, B)> get waitUnwrapped async {
    final r = await _waitAll([$1, $2]);
    return (r[0] as A, r[1] as B);
  }
}

/// Adds [waitUnwrapped] to a triple of futures.
extension FutureRecord3<A, B, C> on (Future<A>, Future<B>, Future<C>) {
  /// All three results, or the first failure thrown as itself.
  Future<(A, B, C)> get waitUnwrapped async {
    final r = await _waitAll([$1, $2, $3]);
    return (r[0] as A, r[1] as B, r[2] as C);
  }
}

/// Adds [waitUnwrapped] to four futures.
extension FutureRecord4<A, B, C, D>
    on (Future<A>, Future<B>, Future<C>, Future<D>) {
  /// All four results, or the first failure thrown as itself.
  Future<(A, B, C, D)> get waitUnwrapped async {
    final r = await _waitAll([$1, $2, $3, $4]);
    return (r[0] as A, r[1] as B, r[2] as C, r[3] as D);
  }
}

/// Adds [waitUnwrapped] to five futures.
extension FutureRecord5<A, B, C, D, E>
    on (Future<A>, Future<B>, Future<C>, Future<D>, Future<E>) {
  /// All five results, or the first failure thrown as itself.
  Future<(A, B, C, D, E)> get waitUnwrapped async {
    final r = await _waitAll([$1, $2, $3, $4, $5]);
    return (r[0] as A, r[1] as B, r[2] as C, r[3] as D, r[4] as E);
  }
}

/// Adds [waitUnwrapped] to seven futures.
extension FutureRecord7<A, B, C, D, E, F, G>
    on
        (
          Future<A>,
          Future<B>,
          Future<C>,
          Future<D>,
          Future<E>,
          Future<F>,
          Future<G>,
        ) {
  /// All seven results, or the first failure thrown as itself.
  Future<(A, B, C, D, E, F, G)> get waitUnwrapped async {
    final r = await _waitAll([$1, $2, $3, $4, $5, $6, $7]);
    return (
      r[0] as A,
      r[1] as B,
      r[2] as C,
      r[3] as D,
      r[4] as E,
      r[5] as F,
      r[6] as G,
    );
  }
}
