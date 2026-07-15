import 'dart:async';

import 'package:datum/source/core/manager/datum_sync_request_strategy.dart';
import 'package:test/test.dart';

void main() {
  group('DatumSyncRequestStrategy', () {
    group('SkipConcurrentStrategy', () {
      late SkipConcurrentStrategy strategy;

      setUp(() {
        strategy = const SkipConcurrentStrategy();
      });

      test('executes action when no sync is in progress', () async {
        var actionExecuted = false;

        final result = await strategy.execute(
          () async {
            actionExecuted = true;
            return 'success';
          },
          isSyncInProgress: () => false,
          onSkipped: () => 'skipped',
        );

        expect(actionExecuted, isTrue);
        expect(result, 'success');
      });

      test('skips action when sync is in progress', () async {
        var actionExecuted = false;

        final result = await strategy.execute(
          () async {
            actionExecuted = true;
            return 'success';
          },
          isSyncInProgress: () => true,
          onSkipped: () => 'skipped',
        );

        expect(actionExecuted, isFalse);
        expect(result, 'skipped');
      });

      test('dispose does nothing', () {
        // Should not throw any exceptions
        expect(() => strategy.dispose(), returnsNormally);
      });
    });

    group('SequentialRequestStrategy', () {
      late SequentialRequestStrategy strategy;

      setUp(() {
        strategy = const SequentialRequestStrategy();
      });

      tearDown(() {
        strategy.dispose();
      });

      test('executes single action immediately', () async {
        var actionExecuted = false;

        final result = await strategy.execute(
          () async {
            actionExecuted = true;
            return 'success';
          },
          isSyncInProgress: () => false,
          onSkipped: () => 'skipped',
        );

        expect(actionExecuted, isTrue);
        expect(result, 'success');
      });

      test('queues multiple actions sequentially', () async {
        // (Previously wrapped in fakeAsync with an async callback, which never
        // actually ran the assertions and left the shared chain frozen in a
        // dead zone — poisoning later tests.)
        final executionOrder = <int>[];
        final futures = <Future<String>>[];

        for (var i = 0; i < 3; i++) {
          futures.add(strategy.execute(
            () async {
              executionOrder.add(i);
              await Future<void>.delayed(const Duration(milliseconds: 10));
              return 'result_$i';
            },
            isSyncInProgress: () => false,
            onSkipped: () => 'skipped',
          ));
        }

        final results = await Future.wait(futures);
        expect(executionOrder, [0, 1, 2]);
        expect(results, ['result_0', 'result_1', 'result_2']);
      });

      test('handles exceptions by propagating them', () async {
        final future = strategy.execute(
          () async {
            throw Exception('Test exception');
          },
          isSyncInProgress: () => false,
          onSkipped: () => 'skipped',
        );

        await expectLater(future, throwsException);
      });

      test('dispose is non-destructive: the strategy keeps working', () async {
        // The default strategy is a canonicalized const instance shared by all
        // managers, so dispose must never tear down the shared chain.
        strategy.dispose();

        final result = await strategy.execute(
          () async => 'success',
          isSyncInProgress: () => false,
          onSkipped: () => 'skipped',
        );

        expect(result, 'success');
      });

      test('retries the action retryCount times then surfaces the error', () async {
        const retrying = SequentialRequestStrategy(retryCount: 2);
        var attempts = 0;
        final future = retrying.execute<int>(
          () async {
            attempts++;
            throw StateError('always fails');
          },
          isSyncInProgress: () => false,
          onSkipped: () => -1,
        );
        // Previously this future NEVER completed (async_queue.retry() does not
        // throw on exhaustion), hanging synchronize() forever.
        await expectLater(future, throwsStateError);
        expect(attempts, 3); // 1 initial + 2 retries
      });

      test('a failing job does not wedge the chain for later jobs', () async {
        const s = SequentialRequestStrategy(retryCount: 0);
        final failing = s.execute<int>(
          () async => throw StateError('boom'),
          isSyncInProgress: () => false,
          onSkipped: () => -1,
        );
        final following = s.execute<int>(
          () async => 42,
          isSyncInProgress: () => false,
          onSkipped: () => -1,
        );
        await expectLater(failing, throwsStateError);
        expect(await following, 42);
      });
    });
  });
}
