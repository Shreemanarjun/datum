import 'package:datum/datum.dart';
import 'package:datum/source/core/manager/cold_start_manager.dart';
import 'package:test/test.dart';

/// A logger that throws only while evaluating the adaptive strategy, so the
/// error surfaces from inside `_shouldPerformColdStartSync` (and nowhere
/// earlier in `handleColdStartIfNeeded`).
class _SelectiveThrowLogger extends DatumLogger {
  _SelectiveThrowLogger() : super(enabled: false);

  bool throwOnAdaptiveEvaluation = true;

  @override
  void debug(String message, {String? category, Map<String, dynamic>? metadata}) {
    if (throwOnAdaptiveEvaluation && message.contains('Evaluating adaptive')) {
      throw Exception('logger boom during strategy evaluation');
    }
  }
}

DatumSyncResult<DatumEntityInterface> _okResult(String userId) => DatumSyncResult<DatumEntityInterface>(
      userId: userId,
      duration: Duration.zero,
      syncedCount: 1,
      failedCount: 0,
      conflictsResolved: 0,
      pendingOperations: const [],
    );

void main() {
  group('ColdStartManager error and retry paths', () {
    test('clears the in-progress flag and rethrows when strategy evaluation throws', () async {
      final logger = _SelectiveThrowLogger();
      final manager = ColdStartManager(
        const ColdStartConfig(
          strategy: ColdStartStrategy.adaptive,
          initialDelay: Duration.zero,
        ),
        logger: logger,
      );

      var syncCalls = 0;
      Future<DatumSyncResult<DatumEntityInterface>> sync(DatumSyncOptions options) async {
        syncCalls++;
        return _okResult('u1');
      }

      await expectLater(
        manager.handleColdStartIfNeeded('u1', sync, synchronous: true),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('logger boom'))),
      );
      expect(syncCalls, 0);

      // The failure path must release the per-user in-progress slot; otherwise
      // this second attempt would be silently skipped.
      logger.throwOnAdaptiveEvaluation = false;
      final handled = await manager.handleColdStartIfNeeded('u1', sync, synchronous: true);
      expect(handled, isTrue);
      expect(syncCalls, 1);
    });

    test('retries a transiently failing sync with backoff and succeeds', () async {
      final manager = ColdStartManager(
        const ColdStartConfig(
          strategy: ColdStartStrategy.fullSync,
          initialDelay: Duration.zero,
        ),
        logger: DatumLogger(enabled: false),
        maxRetries: 2,
        initialRetryDelay: const Duration(milliseconds: 1),
      );

      var attempts = 0;
      Future<DatumSyncResult<DatumEntityInterface>> flakySync(DatumSyncOptions options) async {
        attempts++;
        if (attempts == 1) {
          throw Exception('transient failure');
        }
        return _okResult('u1');
      }

      final handled = await manager.handleColdStartIfNeeded('u1', flakySync, synchronous: true);

      expect(handled, isTrue);
      // First attempt failed, one retry succeeded.
      expect(attempts, 2);
      expect(manager.isColdStartForUser('u1'), isFalse);
      expect(manager.getLastColdStartTimeForUser('u1'), isNotNull);
    });

    test('gives up after exhausting retries and rethrows the last error', () async {
      final manager = ColdStartManager(
        const ColdStartConfig(
          strategy: ColdStartStrategy.fullSync,
          initialDelay: Duration.zero,
        ),
        logger: DatumLogger(enabled: false),
        maxRetries: 1,
        initialRetryDelay: const Duration(milliseconds: 1),
      );

      var attempts = 0;
      Future<DatumSyncResult<DatumEntityInterface>> alwaysFails(DatumSyncOptions options) async {
        attempts++;
        throw Exception('permanent failure');
      }

      await expectLater(
        manager.handleColdStartIfNeeded('u1', alwaysFails, synchronous: true),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('permanent failure'))),
      );

      // Initial attempt + 1 retry.
      expect(attempts, 2);
      // A failed cold start must remain a cold start so it can retry on next launch.
      expect(manager.isColdStartForUser('u1'), isTrue);
    });

    test('throws the retry-logic StateError when configured with negative maxRetries', () async {
      final manager = ColdStartManager(
        const ColdStartConfig(
          strategy: ColdStartStrategy.fullSync,
          initialDelay: Duration.zero,
        ),
        logger: DatumLogger(enabled: false),
        maxRetries: -1,
      );

      var attempts = 0;
      Future<DatumSyncResult<DatumEntityInterface>> sync(DatumSyncOptions options) async {
        attempts++;
        return _okResult('u1');
      }

      await expectLater(
        manager.handleColdStartIfNeeded('u1', sync, synchronous: true),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('Unexpected retry logic error'))),
      );
      // The retry loop never runs when maxRetries is negative.
      expect(attempts, 0);
    });
  });
}
