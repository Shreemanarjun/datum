import 'package:datum/source/core/models/datum_operation.dart';
import 'package:datum/source/core/models/datum_sync_operation.dart';
import 'package:datum/source/core/sync/datum_sync_execution_strategy.dart';
import 'package:flutter_test/flutter_test.dart';

import '../mocks/test_entity.dart';

void main() {
  group('SyncExecutionStrategy', () {
    late List<DatumSyncOperation<TestEntity>> operations;
    late List<String> processedOrder;
    late List<(int, int)> progressUpdates;
    var isCancelled = false;

    setUp(() {
      operations = List.generate(
        5,
        (i) => DatumSyncOperation<TestEntity>(
          id: 'op$i',
          userId: 'user1',
          entityId: 'e$i',
          type: DatumOperationType.create,
          timestamp: DateTime.now(),
        ),
      );
      processedOrder = [];
      progressUpdates = [];
      isCancelled = false;
    });

    Future<void> processOperation(DatumSyncOperation<TestEntity> op) async {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      processedOrder.add(op.id);
    }

    void onProgress(int completed, int total) {
      progressUpdates.add((completed, total));
    }

    group('SequentialStrategy', () {
      test('processes all operations in order', () async {
        // Arrange
        const strategy = SequentialStrategy();

        // Act
        await strategy.execute<TestEntity>(
          operations,
          processOperation,
          () => isCancelled,
          onProgress,
        );

        // Assert
        expect(processedOrder, ['op0', 'op1', 'op2', 'op3', 'op4']);
        expect(progressUpdates, [(1, 5), (2, 5), (3, 5), (4, 5), (5, 5)]);
        expect(progressUpdates.last, (5, 5));
      });

      test('stops processing when cancelled', () async {
        // Arrange
        const strategy = SequentialStrategy();

        // Act
        await strategy.execute<TestEntity>(operations, processOperation, () {
          // Cancel after 2 operations
          if (processedOrder.length >= 2) {
            isCancelled = true;
          }
          return isCancelled;
        }, onProgress);

        // Assert
        expect(processedOrder, ['op0', 'op1']);
        expect(progressUpdates, hasLength(2));
      });

      test('handles empty operation list gracefully', () async {
        // Arrange
        const strategy = SequentialStrategy();

        // Act
        await strategy.execute<TestEntity>(
          [],
          processOperation,
          () => isCancelled,
          onProgress,
        );

        // Assert
        expect(processedOrder, isEmpty);
        expect(progressUpdates, isEmpty);
      });

      test('propagates errors from processOperation', () async {
        // Arrange
        const strategy = SequentialStrategy();
        final exception = Exception('Processing failed');

        // Act
        Future<void> action() async {
          await strategy.execute<TestEntity>(
            operations,
            (op) async {
              if (op.id == 'op2') throw exception;
              await processOperation(op);
            },
            () => isCancelled,
            onProgress,
          );
        }

        // Assert
        // We expect the future to complete with an error.
        await expectLater(action(), throwsA(exception));

        // Verify that operations were processed until the error occurred.
        expect(processedOrder, ['op0', 'op1']);
      });
    });

    group('ParallelStrategy', () {
      test('processes all operations in batches', () async {
        // Arrange
        const strategy = ParallelStrategy(batchSize: 2);

        // Act
        await strategy.execute<TestEntity>(
          operations,
          processOperation,
          () => isCancelled,
          onProgress,
        );

        // Assert
        expect(
          processedOrder,
          unorderedEquals(['op0', 'op1', 'op2', 'op3', 'op4']),
        );
        expect(
          progressUpdates,
          hasLength(3),
        ); // 5 ops in batches of 2 -> 3 batches (2, 2, 1)
        expect(progressUpdates[0], (2, 5));
        expect(progressUpdates[1], (4, 5));
        expect(progressUpdates[2], (5, 5));
      });

      test('stops processing between batches when cancelled', () async {
        // Arrange
        const strategy = ParallelStrategy(batchSize: 2);

        // Act
        await strategy.execute<TestEntity>(operations, processOperation, () {
          // Cancel after the first batch
          if (processedOrder.length >= 2) {
            isCancelled = true;
          }
          return isCancelled;
        }, onProgress);

        // Assert
        expect(processedOrder, hasLength(2)); // Only the first batch
        expect(progressUpdates, hasLength(1));
      });

      test('handles empty operation list gracefully', () async {
        // Arrange
        const strategy = ParallelStrategy(batchSize: 2);

        // Act
        await strategy.execute<TestEntity>(
          [],
          processOperation,
          () => isCancelled,
          onProgress,
        );

        // Assert
        expect(processedOrder, isEmpty);
        expect(progressUpdates, isEmpty);
      });

      test('handles operation list smaller than batch size', () async {
        // Arrange
        const strategy = ParallelStrategy();

        // Act
        await strategy.execute<TestEntity>(
          operations,
          processOperation,
          () => isCancelled,
          onProgress,
        );

        // Assert
        expect(
          processedOrder,
          unorderedEquals(['op0', 'op1', 'op2', 'op3', 'op4']),
        );
        expect(progressUpdates, hasLength(1));
        expect(progressUpdates.last, (5, 5));
      });

      test('propagates errors from processOperation', () async {
        // Arrange
        const strategy = ParallelStrategy(batchSize: 2);
        final exception = Exception('Processing failed');

        // Act
        Future<void> action() async {
          await strategy.execute<TestEntity>(
            operations,
            (op) async {
              if (op.id == 'op2') throw exception;
              await processOperation(op);
            },
            () => isCancelled,
            onProgress,
          );
        }

        // Assert
        // We expect the future to complete with an error.
        await expectLater(action(), throwsA(exception));
      });

      test(
        'processes all batches and throws at the end when failFast is false',
        () async {
          // Isolate state to this test to prevent flakiness in group runs.
          final processedOrder = <String>[];
          final progressUpdates = <(int, int)>[];

          // Arrange
          const strategy = ParallelStrategy(batchSize: 2, failFast: false);
          final exception1 = Exception('Processing failed 1');
          final exception2 = Exception('Processing failed 2');
          // Re-initialize operations to ensure test isolation
          operations = List.generate(
            5,
            (i) => DatumSyncOperation<TestEntity>(
              id: 'op$i',
              userId: 'user1',
              entityId: 'e$i',
              type: DatumOperationType.create,
              timestamp: DateTime.now(),
            ),
          );

          // Define processOperation locally to ensure it captures the correct `processedOrder` list for this test.
          Future<void> localProcessOperation(
            DatumSyncOperation<TestEntity> op,
          ) async {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            processedOrder.add(op.id);
          }

          // Act
          Future<void> action() async {
            await strategy.execute<TestEntity>(
              operations,
              (op) async {
                if (op.id == 'op1') throw exception1;
                if (op.id == 'op4') throw exception2;
                await localProcessOperation(op);
              },
              () => isCancelled,
              (completed, total) => progressUpdates.add((completed, total)),
            );
          }

          // Assert
          // We expect the future to complete with the first error.
          await expectLater(action(), throwsA(exception1));

          // Verify that all non-failing operations were still processed.
          expect(processedOrder, unorderedEquals(['op0', 'op2', 'op3']));
          // All batches should have reported progress.
          expect(progressUpdates, hasLength(3));
        },
      );

      test(
        'propagates first error when multiple operations fail in a batch',
        () async {
          // Arrange
          const strategy = ParallelStrategy(batchSize: 5);
          final exception1 = Exception('Failure 1');
          final exception2 = Exception('Failure 2');

          // Act
          Future<void> action() async {
            await strategy.execute<TestEntity>(
              operations,
              (op) async {
                if (op.id == 'op1') {
                  await Future<void>.delayed(const Duration(milliseconds: 10));
                  throw exception1;
                }
                if (op.id == 'op2') {
                  await Future<void>.delayed(const Duration(milliseconds: 20));
                  throw exception2;
                }
                await processOperation(op);
              },
              () => isCancelled,
              onProgress,
            );
          }

          // Assert
          // The execution should throw the first exception that occurred.
          await expectLater(action(), throwsA(exception1));

          // Other non-failing operations might complete before the exception is thrown.
          expect(processedOrder, isNot(contains('op1')));
        },
      );
    });

    group('IsolateStrategy', () {
      test('processes all operations successfully via isolate', () async {
        // Arrange
        const strategy = IsolateStrategy(SequentialStrategy());

        // Act
        await strategy.execute<TestEntity>(
          operations,
          processOperation,
          () => isCancelled,
          onProgress,
        );

        // Assert
        expect(processedOrder, ['op0', 'op1', 'op2', 'op3', 'op4']);
        expect(progressUpdates, [(1, 5), (2, 5), (3, 5), (4, 5), (5, 5)]);
        expect(progressUpdates.last, (5, 5));
      });

      test('stops processing when cancelled', () async {
        // Arrange
        const strategy = IsolateStrategy(SequentialStrategy());

        // Act
        await strategy.execute<TestEntity>(
          operations,
          (op) async {
            // Wrap the original processOperation to also handle progress updates
            // This ensures progress is reported before the cancellation check runs.
            await processOperation(op);
            onProgress(processedOrder.length, operations.length);
          },
          () {
            // Cancel after 2 operations
            if (processedOrder.length >= 2) isCancelled = true;
            return isCancelled;
          },
          (completed, total) {
            /* No-op, handled in processOperation */
          },
        );

        // Assert
        // Allow a moment for the isolate to be killed and processing to stop.
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(processedOrder, ['op0', 'op1']);
        expect(progressUpdates, hasLength(2));
      });

      test('propagates errors from processOperation', () async {
        // Arrange
        // Localize operations list for this test to ensure isolation
        final localOperations = List.generate(
          5,
          (i) => DatumSyncOperation<TestEntity>(
            id: 'op$i',
            userId: 'user1',
            entityId: 'e$i',
            type: DatumOperationType.create,
            timestamp: DateTime.now(),
          ),
        );
        final processedOrder = <String>[];
        final progressUpdates = <(int, int)>[];
        var isCancelled = false; // Localize cancellation flag too

        Future<void> localProcessOperation(
          DatumSyncOperation<TestEntity> op,
        ) async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          processedOrder.add(op.id);
        }

        void localOnProgress(int completed, int total) {
          progressUpdates.add((completed, total));
        }

        const strategy = IsolateStrategy(SequentialStrategy());
        final exception = Exception('Processing failed in isolate');

        // Act
        Future<void> action() async {
          await strategy.execute<TestEntity>(
            localOperations, // Use localized operations
            (op) async {
              if (op.id == 'op2') throw exception;
              await localProcessOperation(op);
            }, // Use local processOperation
            () => isCancelled, // Use local isCancelled
            localOnProgress, // Use local onProgress
          );
        }

        // Assert
        // Use a try-catch block for a more robust assertion with isolates.
        try {
          await action();
          fail('Expected an exception to be thrown, but none was.');
        } catch (e) {
          expect(e, isA<Exception>());
          expect(
            (e as Exception).toString(),
            contains('Processing failed in isolate'),
          );
        }
      });

      test('handles empty operation list gracefully', () async {
        // Arrange
        const strategy = IsolateStrategy(SequentialStrategy());

        // Act
        await strategy.execute<TestEntity>(
          [],
          processOperation,
          () => isCancelled,
          onProgress,
        );

        // Assert
        expect(processedOrder, isEmpty);
        expect(progressUpdates, isEmpty);
      });
    });
  });
}
