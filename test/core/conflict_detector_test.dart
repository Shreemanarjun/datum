import 'package:datum/source/core/engine/conflict_detector.dart';
import 'package:datum/source/core/models/conflict_context.dart';
import 'package:datum/source/core/models/datum_sync_metadata.dart';
import 'package:test/test.dart';

import '../mocks/test_entity.dart';

void main() {
  group('DatumConflictDetector', () {
    late DatumConflictDetector<TestEntity> detector;

    setUp(() {
      detector = DatumConflictDetector<TestEntity>();
    });

    test('detects no conflict when both items are null', () {
      final context = detector.detect(
        localItem: null,
        remoteItem: null,
        userId: 'user1',
      );

      expect(context, isNull);
    });

    test('detects no conflict when only remote exists', () {
      final remote = TestEntity(
        id: 'entity1',
        userId: 'user1',
        name: 'Remote',
        value: 42,
        modifiedAt: DateTime.now(),
        createdAt: DateTime.now(),
        version: 1,
      );

      final context = detector.detect(
        localItem: null,
        remoteItem: remote,
        userId: 'user1',
      );

      expect(context, isNull);
    });

    test('detects no conflict when only local exists', () {
      final local = TestEntity(
        id: 'entity1',
        userId: 'user1',
        name: 'Local',
        value: 42,
        modifiedAt: DateTime.now(),
        createdAt: DateTime.now(),
        version: 1,
      );

      final context = detector.detect(
        localItem: local,
        remoteItem: null,
        userId: 'user1',
      );

      expect(context, isNull);
    });

    test('detects user mismatch conflict', () {
      final local = TestEntity(
        id: 'entity1',
        userId: 'user1',
        name: 'Local',
        value: 42,
        modifiedAt: DateTime.now(),
        createdAt: DateTime.now(),
        version: 1,
      );

      final remote = TestEntity(
        id: 'entity1',
        userId: 'user2',
        name: 'Remote',
        value: 42,
        modifiedAt: DateTime.now(),
        createdAt: DateTime.now(),
        version: 1,
      );

      final context = detector.detect(
        localItem: local,
        remoteItem: remote,
        userId: 'user1',
      );

      expect(context, isNotNull);
      expect(context!.type, DatumConflictType.userMismatch);
      expect(context.entityId, 'entity1');
    });

    test('detects deletion conflict when one is deleted', () {
      final local = TestEntity(
        id: 'entity1',
        userId: 'user1',
        name: 'Local',
        value: 42,
        modifiedAt: DateTime.now(),
        createdAt: DateTime.now(),
        version: 1,
      );

      final remote = TestEntity(
        id: 'entity1',
        userId: 'user1',
        name: 'Remote',
        value: 42,
        modifiedAt: DateTime.now(),
        createdAt: DateTime.now(),
        version: 1,
        isDeleted: true,
      );

      final context = detector.detect(
        localItem: local,
        remoteItem: remote,
        userId: 'user1',
      );

      expect(context, isNotNull);
      expect(context!.type, DatumConflictType.deletionConflict);
    });

    test('detects deletion conflict when local is deleted and remote is not',
        () {
      final local = TestEntity(
        id: 'entity1',
        userId: 'user1',
        name: 'Local',
        value: 42,
        modifiedAt: DateTime.now(),
        createdAt: DateTime.now(),
        version: 2,
        isDeleted: true,
      );

      final remote = TestEntity(
        id: 'entity1',
        userId: 'user1',
        name: 'Remote',
        value: 42,
        modifiedAt: DateTime.now(),
        createdAt: DateTime.now(),
        version: 1,
        isDeleted: false,
      );

      final context = detector.detect(
        localItem: local,
        remoteItem: remote,
        userId: 'user1',
      );

      expect(context, isNotNull);
      expect(context!.type, DatumConflictType.deletionConflict);
    });

    test('detects both-modified conflict with different versions', () {
      final baseTime = DateTime.now();
      final local = TestEntity(
        id: 'entity1',
        userId: 'user1',
        name: 'Local',
        value: 42,
        modifiedAt: baseTime.add(const Duration(seconds: 10)),
        createdAt: baseTime,
        version: 2,
      );

      final remote = TestEntity(
        id: 'entity1',
        userId: 'user1',
        name: 'Remote',
        value: 100,
        modifiedAt: baseTime.add(const Duration(seconds: 20)),
        createdAt: baseTime,
        version: 3,
      );

      final context = detector.detect(
        localItem: local,
        remoteItem: remote,
        userId: 'user1',
      );

      expect(context, isNotNull);
      expect(context!.type, DatumConflictType.bothModified);
    });

    test('no conflict when same version despite time difference', () {
      final baseTime = DateTime.now();
      final local = TestEntity(
        id: 'entity1',
        userId: 'user1',
        name: 'Local',
        value: 42,
        modifiedAt: baseTime.add(const Duration(seconds: 10)),
        createdAt: baseTime,
        version: 2,
      );

      final remote = TestEntity(
        id: 'entity1',
        userId: 'user1',
        name: 'Remote',
        value: 42,
        modifiedAt: baseTime.add(const Duration(seconds: 20)),
        createdAt: baseTime,
        version: 2,
      );

      final context = detector.detect(
        localItem: local,
        remoteItem: remote,
        userId: 'user1',
      );

      expect(context, isNull);
    });

    test('detects no conflict when items are identical', () {
      final now = DateTime.now();
      final item = TestEntity(
        id: 'entity1',
        userId: 'user1',
        name: 'Item',
        value: 42,
        modifiedAt: now,
        createdAt: now,
        version: 2,
      );

      final context = detector.detect(
        localItem: item,
        remoteItem: item,
        userId: 'user1',
      );

      expect(context, isNull);
    });

    test('detects user mismatch even when local item is null', () {
      // This is an important security/data-integrity check.
      // It prevents an item belonging to another user from being pulled
      // down and created for the current user.
      final remote = TestEntity(
        id: 'entity1',
        userId: 'user2', // Belongs to a different user
        name: 'Remote',
        value: 42,
        modifiedAt: DateTime.now(),
        createdAt: DateTime.now(),
        version: 1,
      );

      final context = detector.detect(
        localItem: null,
        remoteItem: remote,
        userId: 'user1', // Current sync context is for user1
      );

      expect(context, isNotNull);
      expect(context!.type, DatumConflictType.userMismatch);
      expect(context.entityId, 'entity1');
    });

    test('includes metadata in conflict context', () {
      final baseTime = DateTime.now();
      final local = TestEntity(
        id: 'entity1',
        userId: 'user1',
        name: 'Local',
        value: 42,
        modifiedAt: baseTime.add(const Duration(seconds: 10)),
        createdAt: baseTime,
        version: 2,
      );

      final remote = TestEntity(
        id: 'entity1',
        userId: 'user1',
        name: 'Remote',
        value: 100,
        modifiedAt: baseTime.add(const Duration(seconds: 20)),
        createdAt: baseTime,
        version: 3,
      );

      final localMetadata = DatumSyncMetadata(
        userId: 'user1',
        lastSyncTime: baseTime,
        dataHash: 'hash1',
        entityCounts: const {
          'TestEntity': DatumEntitySyncDetails(count: 1, hash: 'hash1'),
        },
      );

      final remoteMetadata = DatumSyncMetadata(
        userId: 'user1',
        lastSyncTime: baseTime.add(const Duration(minutes: 1)),
        dataHash: 'hash2',
        entityCounts: const {
          'TestEntity': DatumEntitySyncDetails(count: 1, hash: 'hash2'),
        },
      );

      final context = detector.detect(
        localItem: local,
        remoteItem: remote,
        userId: 'user1',
        localMetadata: localMetadata,
        remoteMetadata: remoteMetadata,
      );

      expect(context, isNotNull);
      expect(context!.localMetadata, equals(localMetadata));
      expect(context.remoteMetadata, equals(remoteMetadata));
    });
  });
}
