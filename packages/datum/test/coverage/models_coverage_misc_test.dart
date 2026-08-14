import 'package:datum/datum.dart';
import 'package:test/test.dart';

import '../mocks/test_entity.dart';

void main() {
  final createdAt = DateTime.utc(2024);
  final modifiedAt = DateTime.utc(2024, 1, 2);

  ExcludableEntity buildExcludable() => ExcludableEntity(
        id: 'ex-1',
        userId: 'user-1',
        name: 'excludable',
        modifiedAt: modifiedAt,
        createdAt: createdAt,
        version: 1,
        localOnlyFields: const {'draft': true},
        remoteOnlyFields: const {'serverToken': 'abc'},
      );

  group('VectorClock', () {
    test('toString includes the internal clock map', () {
      final clock = const VectorClock({}).increment('replica-a').increment('replica-a');
      expect(clock.toString(), 'VectorClock({replica-a: 2})');
    });
  });

  group('DatumEntityMixin defaults', () {
    test('merge returns the other entity', () {
      final a = buildExcludable();
      final b = buildExcludable().copyWith(name: 'newer');
      expect(a.merge(b), same(b));
    });
  });

  group('ExcludableEntity', () {
    test('diff against a different entity type returns the full remote map', () {
      final entity = buildExcludable();
      final unrelated = TestEntity.create('t-1', 'user-1', 'other');

      final diff = entity.diff(unrelated);
      expect(diff, equals(entity.toDatumMap(target: MapTarget.remote)));
      expect(diff, contains('serverToken'));
      expect(diff, isNot(contains('draft')));
    });

    test('stringify produces a descriptive toString', () {
      final entity = buildExcludable();
      final text = entity.toString();
      expect(text, contains('ExcludableEntity'));
      expect(text, contains('excludable'));
    });
  });

  group('RelationDescriptor', () {
    test('toString reports name, kind, target and keys', () {
      const descriptor = RelationDescriptor(
        name: 'posts',
        kind: RelationKind.hasMany,
        targetType: TestEntity,
        foreignKey: 'userId',
        localKey: 'id',
      );

      final text = descriptor.toString();
      expect(text, contains('posts'));
      expect(text, contains('RelationKind.hasMany'));
      expect(text, contains('TestEntity'));
      expect(text, contains('fk=userId'));
      expect(text, contains('lk=id'));
    });
  });

  group('DatumRelationSchema', () {
    tearDown(DatumRelationSchema.clear);

    test('registeredTypes lists every registered entity type', () {
      DatumRelationSchema.clear();
      expect(DatumRelationSchema.registeredTypes, isEmpty);

      DatumRelationSchema.register(TestEntity, const {
        'posts': RelationDescriptor(
          name: 'posts',
          kind: RelationKind.hasMany,
          targetType: TestEntity,
          foreignKey: 'userId',
          localKey: 'id',
        ),
      });

      expect(DatumRelationSchema.registeredTypes, contains(TestEntity));
      expect(DatumRelationSchema.isRegistered(TestEntity), isTrue);
      expect(DatumRelationSchema.of(TestEntity), contains('posts'));
    });
  });

  group('PaginationConfig', () {
    test('stores page size, page and cursor', () {
      var pageSize = 25;
      final config = PaginationConfig(pageSize: pageSize, currentPage: 2, cursor: 'c-1');
      expect(config.pageSize, 25);
      expect(config.currentPage, 2);
      expect(config.cursor, 'c-1');
      expect(config, equals(PaginationConfig(pageSize: pageSize, currentPage: 2, cursor: 'c-1')));
      expect(config.toString(), contains('PaginationConfig'));
    });
  });

  group('PaginatedResult', () {
    test('empty() builds a result with no items and no more pages', () {
      // ignore: prefer_const_constructors
      final result = PaginatedResult<TestEntity>.empty();
      expect(result.items, isEmpty);
      expect(result.totalCount, 0);
      expect(result.currentPage, 1);
      expect(result.totalPages, 0);
      expect(result.hasMore, isFalse);
      expect(result.nextCursor, isNull);
    });
  });

  group('Backoff strategies', () {
    test('LinearBackoff scales the increment by attempt number', () {
      var seconds = 2;
      final backoff = LinearBackoff(increment: Duration(seconds: seconds));
      expect(backoff.getDelay(1), const Duration(seconds: 2));
      expect(backoff.getDelay(3), const Duration(seconds: 6));
    });

    test('FixedBackoff always returns the same delay', () {
      var millis = 250;
      final backoff = FixedBackoff(delay: Duration(milliseconds: millis));
      expect(backoff.getDelay(1), const Duration(milliseconds: 250));
      expect(backoff.getDelay(10), const Duration(milliseconds: 250));
    });
  });

  group('DatumSyncBatchOperation', () {
    DatumSyncOperation<TestEntity> buildOp(String id, {int size = 10}) => DatumSyncOperation<TestEntity>(
          id: id,
          userId: 'user-1',
          entityId: 'entity-$id',
          type: DatumOperationType.create,
          timestamp: DateTime.utc(2024, 5, 1),
          sizeInBytes: size,
        );

    test('props include the wrapped operations', () {
      final batchA = DatumSyncBatchOperation<TestEntity>(
        operations: [buildOp('op-1'), buildOp('op-2', size: 20)],
      );
      final batchB = DatumSyncBatchOperation<TestEntity>(
        operations: [buildOp('op-1'), buildOp('op-2', size: 20)],
      );
      final batchC = DatumSyncBatchOperation<TestEntity>(
        operations: [buildOp('op-1')],
      );

      expect(batchA.id, 'batch_op-1');
      expect(batchA.sizeInBytes, 30);
      expect(batchA.props, contains(batchA.operations));
      expect(batchA, equals(batchB));
      expect(batchA.hashCode, equals(batchB.hashCode));
      expect(batchA, isNot(equals(batchC)));
    });
  });
}
