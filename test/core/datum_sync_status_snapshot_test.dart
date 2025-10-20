import 'package:datum/source/core/health/datum_health.dart';
import 'package:datum/source/core/models/datum_sync_status_snapshot.dart';
import 'package:test/test.dart';

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
      expect(snapshot.lastStartedAt, isNull);
      expect(snapshot.lastCompletedAt, isNull);
      expect(snapshot.errors, isEmpty);
      expect(snapshot.syncedCount, 0);
      expect(snapshot.conflictsResolved, 0);
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

    group('Equality and HashCode', () {
      final now = DateTime.now();
      final health = const DatumHealth(status: DatumSyncHealth.syncing);
      final errors = [Exception('Test')];
      final snapshot1 = DatumSyncStatusSnapshot(
        userId: 'user1',
        status: DatumSyncStatus.syncing,
        pendingOperations: 5,
        completedOperations: 2,
        failedOperations: 1,
        progress: 0.4,
        lastStartedAt: now,
        errors: errors,
        syncedCount: 2,
        conflictsResolved: 1,
        health: health,
      );

      test('instances with same values are equal', () {
        final snapshot2 = DatumSyncStatusSnapshot(
          userId: 'user1',
          status: DatumSyncStatus.syncing,
          pendingOperations: 5,
          completedOperations: 2,
          failedOperations: 1,
          progress: 0.4,
          lastStartedAt: now,
          errors: errors,
          syncedCount: 2,
          conflictsResolved: 1,
          health: health,
        );

        expect(snapshot1, equals(snapshot2));
        expect(snapshot1.hashCode, equals(snapshot2.hashCode));
      });

      test('instances with different values are not equal', () {
        final differentStatus =
            snapshot1.copyWith(status: DatumSyncStatus.completed);
        final differentPending = snapshot1.copyWith(pendingOperations: 10);
        final differentProgress = snapshot1.copyWith(progress: 0.8);
        final differentHealth = snapshot1.copyWith(
          health: const DatumHealth(status: DatumSyncHealth.healthy),
        );

        expect(snapshot1, isNot(equals(differentStatus)));
        expect(snapshot1, isNot(equals(differentPending)));
        expect(snapshot1, isNot(equals(differentProgress)));
        expect(snapshot1, isNot(equals(differentHealth)));
      });

      test('instances with different error lists are not equal', () {
        final differentErrors = snapshot1.copyWith(errors: []);
        expect(snapshot1, isNot(equals(differentErrors)));
      });
    });

    test('toString provides a useful representation', () {
      final now = DateTime.now();
      final snapshot = DatumSyncStatusSnapshot(
        userId: 'user-xyz',
        status: DatumSyncStatus.syncing,
        pendingOperations: 10,
        completedOperations: 5,
        failedOperations: 1,
        progress: 0.5,
        lastStartedAt: now,
        errors: [Exception('Network Error')],
        syncedCount: 4,
        conflictsResolved: 1,
        health: const DatumHealth(status: DatumSyncHealth.degraded),
      );

      final stringRepresentation = snapshot.toString();

      expect(stringRepresentation, contains('userId: user-xyz'));
      expect(stringRepresentation, contains('status: DatumSyncStatus.syncing'));
      expect(stringRepresentation, contains('pendingOperations: 10'));
      expect(stringRepresentation, contains('completedOperations: 5'));
      expect(stringRepresentation, contains('failedOperations: 1'));
      expect(stringRepresentation, contains('progress: 0.5'));
      expect(stringRepresentation, contains('lastStartedAt: $now'));
      expect(
          stringRepresentation, contains('errors: [Exception: Network Error]'));
      expect(stringRepresentation, contains('syncedCount: 4'));
      expect(stringRepresentation, contains('conflictsResolved: 1'));
      expect(
        stringRepresentation,
        contains(
          'health: DatumHealth(DatumSyncHealth.degraded, AdapterHealthStatus.ok, AdapterHealthStatus.ok)',
        ),
      );
    });
  });
}
