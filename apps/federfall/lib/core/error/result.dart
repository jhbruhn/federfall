import 'package:flutter/foundation.dart';

/// A synchronous success-or-failure outcome.
///
/// For async flows, Riverpod's `AsyncValue` already plays this role; [Result]
/// is for one-shot imperative actions (form submits, button handlers) where a
/// plain try/catch would otherwise leak through the call stack. Use [guard] to
/// run a future and capture its outcome.
@immutable
sealed class Result<T> {
  const Result();

  /// A successful result carrying [value].
  const factory Result.ok(T value) = Ok<T>;

  /// A failed result carrying [error] (and optional [stackTrace]).
  const factory Result.err(Object error, [StackTrace? stackTrace]) = Err<T>;

  /// Runs [op], returning [Ok] on success or [Err] on any thrown error.
  static Future<Result<T>> guard<T>(Future<T> Function() op) async {
    try {
      return Ok(await op());
    } on Object catch (error, stackTrace) {
      return Err(error, stackTrace);
    }
  }

  /// Whether this is an [Ok].
  bool get isOk => this is Ok<T>;

  /// Whether this is an [Err].
  bool get isErr => this is Err<T>;

  /// The value if [Ok], else `null`.
  T? get valueOrNull => switch (this) {
        Ok<T>(:final value) => value,
        Err<T>() => null,
      };

  /// Folds both cases into a single value.
  R fold<R>({
    required R Function(T value) ok,
    required R Function(Object error) err,
  }) =>
      switch (this) {
        Ok<T>(:final value) => ok(value),
        Err<T>(:final error) => err(error),
      };
}

/// Successful [Result].
final class Ok<T> extends Result<T> {
  const Ok(this.value);

  final T value;

  @override
  bool operator ==(Object other) => other is Ok<T> && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// Failed [Result].
final class Err<T> extends Result<T> {
  const Err(this.error, [this.stackTrace]);

  final Object error;
  final StackTrace? stackTrace;

  @override
  bool operator ==(Object other) => other is Err<T> && other.error == error;

  @override
  int get hashCode => error.hashCode;
}
