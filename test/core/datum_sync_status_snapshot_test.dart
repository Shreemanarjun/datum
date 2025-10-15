import 'package:datum/source/core/sync/datum_sync_status_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DatumSyncStatusSnapshot', () {
    test('initial factory creates a correct snapshot', () {
      final snapshot = DatumSyncStatusSnapshot.initial('user1');

      expect(snapshot.userId, 'user1');
      expect(snapshot.status, DatumSyncStatus.idle);
      expect(snapshot.pendingOperations, 0);
      expect(snapshot.completedOperations, 0);
      expect(snapshot.failedOperations, 0);
      expect(snapshot.progress, 0.0);
      expect(snapshot.hasUnsyncedData, isFalse);
      expect(snapshot.hasFailures, isFalse);
    });

    test('hasUnsyncedData returns true when pendingOperations > 0', () {
      final snapshot = DatumSyncStatusSnapshot.initial(
        'user1',
      ).copyWith(pendingOperations: 5);
      expect(snapshot.hasUnsyncedData, isTrue);
    });

    test('hasUnsyncedData returns false when pendingOperations is 0', () {
      final snapshot = DatumSyncStatusSnapshot.initial(
        'user1',
      ).copyWith(pendingOperations: 0);
      expect(snapshot.hasUnsyncedData, isFalse);
    });

    test('hasFailures returns true when failedOperations > 0', () {
      final snapshot = DatumSyncStatusSnapshot.initial(
        'user1',
      ).copyWith(failedOperations: 1);
      expect(snapshot.hasFailures, isTrue);
    });

    test('hasFailures returns false when failedOperations is 0', () {
      final snapshot = DatumSyncStatusSnapshot.initial(
        'user1',
      ).copyWith(failedOperations: 0);
      expect(snapshot.hasFailures, isFalse);
    });

    test('copyWith creates a new instance with updated values', () {
      final initial = DatumSyncStatusSnapshot.initial('user1');
      final now = DateTime.now();
      final copied = initial.copyWith(
        status: DatumSyncStatus.syncing,
        pendingOperations: 10,
        progress: 0.5,
        lastStartedAt: now,
        errors: [Exception('Test Error')],
      );

      expect(copied.status, DatumSyncStatus.syncing);
      expect(copied.pendingOperations, 10);
      expect(copied.progress, 0.5);
      expect(copied.lastStartedAt, now);
      expect(copied.errors, hasLength(1));
      expect(copied.userId, initial.userId); // Unchanged
    });

    test(
      'copyWith creates an identical copy when no arguments are provided',
      () {
        final initial = DatumSyncStatusSnapshot.initial('user1');
        final copied = initial.copyWith();
        expect(copied.status, initial.status);
        expect(copied.pendingOperations, initial.pendingOperations);
      },
    );
  });
}
