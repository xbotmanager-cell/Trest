import 'dart:async';
import 'package:hey_dane/app/core/errors/ai_exception.dart';

class RetryPolicy {
  const RetryPolicy({
    this.maxAttempts = 3,
    this.initialDelay = const Duration(milliseconds: 450),
    this.backoffFactor = 2.0,
  });

  final int maxAttempts;
  final Duration initialDelay;
  final double backoffFactor;

  Future<T> execute<T>(
    Future<T> Function() operation, {
    bool Function()? isCancelled,
  }) async {
    var attempt = 0;
    var delay = initialDelay;

    while (true) {
      if (isCancelled?.call() == true) {
        throw const AiException(
          kind: AiErrorKind.cancelled,
          message: 'Request cancelled by user.',
        );
      }

      attempt += 1;
      try {
        return await operation();
      } on AiException catch (error) {
        if (!error.retryable || attempt >= maxAttempts) {
          rethrow;
        }
      }

      await Future<void>.delayed(delay);
      delay = Duration(
        milliseconds: (delay.inMilliseconds * backoffFactor).round(),
      );
    }
  }
}
