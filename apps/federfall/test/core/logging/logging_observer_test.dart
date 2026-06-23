import 'package:federfall/core/logging/app_logger.dart';
import 'package:federfall/core/logging/logging_observer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Captures logged errors instead of writing to dart:developer.
class _CapturingLogger extends AppLogger {
  final errors = <Object?>[];

  @override
  void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    String? name,
  }) {
    errors.add(error);
  }
}

final _boomProvider = Provider<int>((ref) => throw StateError('boom'));

void main() {
  test('logs provider failures through AppLogger', () {
    final logger = _CapturingLogger();
    final container = ProviderContainer(
      observers: [LoggingProviderObserver(logger)],
    );
    addTearDown(container.dispose);

    expect(() => container.read(_boomProvider), throwsA(anything));
    expect(logger.errors, isNotEmpty);
  });
}
