import 'package:datum/datum.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DatumBackoffStrategy', () {
    group('ExponentialBackoff', () {
      test(
        'getDelay calculates correct exponential delay with default values',
        () async {
          const strategy = ExponentialBackoff();
          expect(strategy.getDelay(1), const Duration(seconds: 1)); // 1 * 2^0
          expect(strategy.getDelay(2), const Duration(seconds: 2)); // 1 * 2^1
          expect(strategy.getDelay(3), const Duration(seconds: 4)); // 1 * 2^2
          expect(strategy.getDelay(4), const Duration(seconds: 8)); // 1 * 2^3
        },
      );

      test(
        'getDelay calculates correct exponential delay with custom values',
        () async {
          const strategy = ExponentialBackoff(
            baseDelay: Duration(milliseconds: 100),
            multiplier: 3.0,
          );
          expect(
            strategy.getDelay(1),
            const Duration(milliseconds: 100),
          ); // 100 * 3^0
          expect(
            strategy.getDelay(2),
            const Duration(milliseconds: 300),
          ); // 100 * 3^1
          expect(
            strategy.getDelay(3),
            const Duration(milliseconds: 900),
          ); // 100 * 3^2
        },
      );

      test('getDelay respects maxDelay', () async {
        const strategy = ExponentialBackoff(
          baseDelay: Duration(seconds: 1),
          maxDelay: Duration(seconds: 5),
        );
        expect(strategy.getDelay(1), const Duration(seconds: 1));
        expect(strategy.getDelay(2), const Duration(seconds: 2));
        expect(strategy.getDelay(3), const Duration(seconds: 4));
        expect(
          strategy.getDelay(4),
          const Duration(seconds: 5),
        ); // Capped at 5s (would be 8s)
        expect(
          strategy.getDelay(5),
          const Duration(seconds: 5),
        ); // Capped at 5s (would be 16s)
      });
    });

    group('LinearBackoff', () {
      test(
        'getDelay calculates correct linear delay with default values',
        () async {
          const strategy = LinearBackoff();
          expect(strategy.getDelay(1), const Duration(seconds: 5)); // 5 * 1
          expect(strategy.getDelay(2), const Duration(seconds: 10)); // 5 * 2
          expect(strategy.getDelay(3), const Duration(seconds: 15)); // 5 * 3
        },
      );

      test(
        'getDelay calculates correct linear delay with custom increment',
        () async {
          const strategy = LinearBackoff(increment: Duration(seconds: 2));
          expect(strategy.getDelay(1), const Duration(seconds: 2)); // 2 * 1
          expect(strategy.getDelay(2), const Duration(seconds: 4)); // 2 * 2
          expect(strategy.getDelay(3), const Duration(seconds: 6)); // 2 * 3
        },
      );
    });

    group('FixedBackoff', () {
      test(
        'getDelay returns the same fixed delay with default values',
        () async {
          const strategy = FixedBackoff();
          expect(strategy.getDelay(1), const Duration(seconds: 5));
          expect(strategy.getDelay(2), const Duration(seconds: 5));
          expect(strategy.getDelay(100), const Duration(seconds: 5));
        },
      );

      test(
        'getDelay returns the same fixed delay with a custom delay',
        () async {
          const strategy = FixedBackoff(delay: Duration(seconds: 10));
          expect(strategy.getDelay(1), const Duration(seconds: 10));
          expect(strategy.getDelay(2), const Duration(seconds: 10));
          expect(strategy.getDelay(100), const Duration(seconds: 10));
        },
      );
    });

    group('CustomBackoff', () {
      test('getDelay uses the provided delayCalculator function', () async {
        final strategy = CustomBackoff(
          (attempt) => Duration(seconds: attempt * 3),
        );

        expect(await strategy.getDelay(1), const Duration(seconds: 3));
        expect(await strategy.getDelay(2), const Duration(seconds: 6));
        expect(await strategy.getDelay(3), const Duration(seconds: 9));
      });

      test('getDelay can implement a fixed list of delays', () async {
        final delays = [
          const Duration(milliseconds: 100),
          const Duration(milliseconds: 500),
          const Duration(seconds: 2),
        ];

        // If attempt is out of bounds, return the last delay
        final strategy = CustomBackoff((attempt) {
          if (attempt > delays.length) {
            return delays.last;
          }
          return delays[attempt - 1];
        });

        expect(await strategy.getDelay(1), const Duration(milliseconds: 100));
        expect(await strategy.getDelay(2), const Duration(milliseconds: 500));
        expect(await strategy.getDelay(3), const Duration(seconds: 2));
        // Test edge case where attempt number is higher than the list length
        expect(await strategy.getDelay(4), const Duration(seconds: 2));
        expect(await strategy.getDelay(100), const Duration(seconds: 2));
      });

      test('getDelay handles Duration.zero correctly', () async {
        final strategy = CustomBackoff((attempt) => Duration.zero);
        expect(await strategy.getDelay(1), Duration.zero);
        expect(await strategy.getDelay(5), Duration.zero);
      });

      test('getDelay can use an async delayCalculator', () async {
        // This test demonstrates the new async capability.
        final strategy = CustomBackoff((attempt) async {
          // Simulate an async operation, like fetching a value.
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return Duration(seconds: attempt);
        });

        expect(await strategy.getDelay(1), const Duration(seconds: 1));
        expect(await strategy.getDelay(2), const Duration(seconds: 2));
      });
    });

    group('DatumErrorRecoveryStrategy', () {
      test('constructor assigns properties correctly', () async {
        Future<bool> shouldRetryFn(DatumException error) async => true;
        Future<void> onErrorFn(DatumException error) async {}
        const backoff = FixedBackoff();

        final strategy = DatumErrorRecoveryStrategy(
          shouldRetry: shouldRetryFn,
          onError: onErrorFn,
          maxRetries: 5,
          backoffStrategy: backoff,
        );

        expect(strategy.shouldRetry, shouldRetryFn);
        expect(strategy.onError, onErrorFn);
        expect(strategy.maxRetries, 5);
        expect(strategy.backoffStrategy, backoff);
      });
    });
  });
}
