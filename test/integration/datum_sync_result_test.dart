import 'package:datum/datum.dart';
import 'package:test/test.dart';
import '../mocks/test_entity.dart';

void main() {
  group('DatumSyncResult', () {
    const userId = 'test-user';

    test('default constructor creates a successful result', () {
      const result = DatumSyncResult(
        userId: userId,
        syncedCount: 5,
        failedCount: 0,
        conflictsResolved: 1,
        pendingOperations: <DatumSyncOperation<TestEntity>>[],
        duration: Duration(seconds: 10),
      );

      expect(result.userId, userId);
      expect(result.syncedCount, 5);
      expect(result.failedCount, 0);
      expect(result.conflictsResolved, 1);
      expect(result.pendingOperations, isEmpty);
      expect(result.duration, const Duration(seconds: 10));
      expect(result.isSuccess, isTrue);
      expect(result.wasSkipped, isFalse);
      expect(result.wasCancelled, isFalse);
      expect(result.error, isNull);
    });

    test('skipped constructor creates a skipped result', () {
      final result = DatumSyncResult.skipped(userId, 5);

      expect(result.userId, userId);
      expect(result.wasSkipped, isTrue);
      expect(result.isSuccess, isFalse);
      expect(result.wasCancelled, isFalse);
      expect(result.syncedCount, 0);
      expect(result.failedCount, 0);
      expect(result.duration, Duration.zero);
    });

    test('cancelled constructor creates a cancelled result', () {
      const result = DatumSyncResult.cancelled(userId, 3);

      expect(result.userId, userId);
      expect(result.wasCancelled, isTrue);
      expect(result.syncedCount, 3);
      expect(result.isSuccess, isFalse);
      expect(result.wasSkipped, isFalse);
      expect(result.failedCount, 0);
      expect(result.duration, Duration.zero);
    });

    test('toString() provides a useful summary', () {
      final result = DatumSyncResult(
        userId: userId,
        syncedCount: 10,
        failedCount: 2,
        conflictsResolved: 1,
        pendingOperations: List.generate(
          3,
          (i) => DatumSyncOperation(
            id: 'op$i',
            userId: userId,
            entityId: 'e$i',
            type: DatumOperationType.create,
            timestamp: DateTime.now(),
          ),
        ),
        duration: const Duration(milliseconds: 123),
      );

      final string = result.toString();
      expect(string, contains('userId: $userId'));
      expect(string, contains('synced: 10'));
      expect(string, contains('failed: 2')); // This seems to be the issue
      expect(string, contains('conflicts: 1'));
      expect(string, contains('duration: 123ms'));
    });

    test('toString() provides a useful summary for a skipped result', () {
      final result = DatumSyncResult<TestEntity>.skipped(
        userId,
        5,
        reason: 'Offline',
      );

      final string = result.toString();
      expect(string, 'DatumSyncResult(userId: $userId, status: skipped, reason: Offline)');
    });

    test('toString() provides a useful summary for a cancelled result', () {
      const result = DatumSyncResult<TestEntity>.cancelled(userId, 3);

      final string = result.toString();
      expect(string, 'DatumSyncResult(userId: $userId, status: cancelled)');
    });
  });
}
