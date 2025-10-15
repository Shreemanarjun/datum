import 'package:flutter_test/flutter_test.dart';
import 'package:datum/datum.dart';

import '../mocks/test_entity.dart';

void main() {
  group('DatumSyncEvent toString()', () {
    const userId = 'user-123';
    final timestamp = DateTime(2023, 1, 1, 10, 30);

    test('DatumSyncEvent base class', () {
      // Abstract class, tested via a concrete implementation
      final event = DatumSyncStartedEvent(
        userId: userId,
        pendingOperations: 5,
        timestamp: timestamp,
      );
      expect(
        event.toString(),
        contains('DatumSyncEvent(userId: $userId, timestamp: $timestamp)'),
      );
    });

    test('DatumSyncStartedEvent', () {
      final event = DatumSyncStartedEvent(
        userId: userId,
        pendingOperations: 10,
        timestamp: timestamp,
      );
      expect(event.userId, userId);
      expect(event.pendingOperations, 10);
      expect(
        event.toString(),
        'DatumSyncEvent(userId: $userId, timestamp: $timestamp): DatumSyncStartedEvent(pendingOperations: 10)',
      );
    });

    test('DatumSyncProgressEvent', () {
      final event = DatumSyncProgressEvent(
        userId: userId,
        completed: 5,
        total: 10,
        timestamp: timestamp,
      );
      expect(event.completed, 5);
      expect(event.total, 10);
      expect(event.progress, 0.5);
      expect(
        event.toString(),
        'DatumSyncEvent(userId: $userId, timestamp: $timestamp): DatumSyncProgressEvent(completed: 5, total: 10, progress: 0.5)',
      );
    });

    test('DatumSyncCompletedEvent', () {
      const result = DatumSyncResult(
        userId: userId,
        syncedCount: 8,
        failedCount: 2,
        conflictsResolved: 0,
        pendingOperations: [],
        duration: Duration.zero,
      );
      final event = DatumSyncCompletedEvent(
        userId: userId,
        result: result,
        timestamp: timestamp,
      );
      expect(event.result, result);
      expect(
        event.toString(),
        'DatumSyncEvent(userId: $userId, timestamp: $timestamp): DatumSyncCompletedEvent(result: $result)',
      );
    });

    test('DatumSyncErrorEvent', () {
      final error = Exception('Network timeout');
      final stackTrace = StackTrace.current;
      final event = DatumSyncErrorEvent(
        userId: userId,
        error: error,
        stackTrace: stackTrace,
        timestamp: timestamp,
      );
      expect(event.error, error);
      expect(event.stackTrace, stackTrace);
      expect(
        event.toString(),
        'DatumSyncEvent(userId: $userId, timestamp: $timestamp): DatumSyncErrorEvent(error: $error, stackTrace: $stackTrace)',
      );
    });

    test('UserSwitchedEvent', () {
      final event = UserSwitchedEvent(
        previousUserId: 'user-old',
        newUserId: 'user-new',
        hadUnsyncedData: true,
        timestamp: timestamp,
      );
      expect(event.previousUserId, 'user-old');
      expect(event.newUserId, 'user-new');
      expect(event.hadUnsyncedData, isTrue);
      expect(
        event.toString(),
        'DatumSyncEvent(userId: user-new, timestamp: $timestamp): UserSwitchedEvent(previousUserId: user-old, newUserId: user-new, hadUnsyncedData: true)',
      );
    });

    test('DataChangeEvent', () {
      final entity = TestEntity.create('entity-1', userId, 'Test');
      final event = DataChangeEvent<TestEntity>(
        userId: userId,
        data: entity,
        changeType: ChangeType.created,
        source: DataSource.local,
        timestamp: timestamp,
      );
      expect(event.data, entity);
      expect(event.changeType, ChangeType.created);
      expect(event.source, DataSource.local);
      expect(
        event.toString(),
        'DatumSyncEvent(userId: $userId, timestamp: $timestamp): DataChangeEvent(data: $entity, changeType: ChangeType.created, source: DataSource.local)',
      );
    });

    test('InitialSyncEvent', () {
      final entity = TestEntity.create('entity-1', userId, 'Test');
      final event = InitialSyncEvent<TestEntity>(
        userId: userId,
        data: [entity],
        timestamp: timestamp,
      );
      expect(event.data, [entity]);
      expect(
        event.toString(),
        'DatumSyncEvent(userId: $userId, timestamp: $timestamp): InitialSyncEvent(data: [$entity])',
      );
    });

    test('ConflictDetectedEvent', () {
      final local = TestEntity.create('e1', userId, 'Local');
      final remote = local.copyWith(name: 'Remote');
      final context = DatumConflictContext(
        userId: userId,
        entityId: 'entity-1',
        type: DatumConflictType.bothModified,
        detectedAt: timestamp,
      );
      final event = ConflictDetectedEvent<TestEntity>(
        userId: userId,
        context: context,
        localData: local,
        remoteData: remote,
        timestamp: timestamp,
      );
      expect(event.context, context);
      expect(event.localData, local);
      expect(event.remoteData, remote);
      expect(
        event.toString(),
        'DatumSyncEvent(userId: $userId, timestamp: $timestamp): ConflictDetectedEvent(context: $context, localData: $local, remoteData: $remote)',
      );
    });

    test('ConflictResolvedEvent', () {
      final resolution = DatumConflictResolution<TestEntity>.useLocal(
        TestEntity.create('e1', userId, 'Winner'),
      );
      final event = ConflictResolvedEvent<TestEntity>(
        userId: userId,
        entityId: 'e1',
        resolution: resolution,
        timestamp: timestamp,
      );
      expect(event.entityId, 'e1');
      expect(event.resolution, resolution);
      expect(
        event.toString(),
        'DatumSyncEvent(userId: $userId, timestamp: $timestamp): ConflictResolvedEvent(entityId: e1, resolution: $resolution)',
      );
    });
  });
}
