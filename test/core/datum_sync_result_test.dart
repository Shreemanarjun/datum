import 'package:datum/datum.dart';
import 'package:test/test.dart';

class TestEntity extends DatumEntity {
  @override
  final String id;
  @override
  final String userId;
  @override
  final DateTime modifiedAt;
  @override
  final DateTime createdAt;
  @override
  final int version;
  @override
  final bool isDeleted;

  const TestEntity({
    required this.id,
    required this.userId,
    required this.modifiedAt,
    required this.createdAt,
    this.version = 1,
    this.isDeleted = false,
  });

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {};
  @override
  TestEntity copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) => this;
  @override
  Map<String, dynamic>? diff(DatumEntity oldVersion) => null;
}

void main() {
  group('DatumSyncResult', () {
    group('toMap and fromMap', () {
      final originalResult = DatumSyncResult<TestEntity>(
        userId: 'user-123',
        duration: const Duration(seconds: 5),
        syncedCount: 10,
        failedCount: 2,
        conflictsResolved: 1,
        pendingOperations: const [], // This field is not serialized
        totalBytesPushed: 2048,
        totalBytesPulled: 4096,
        bytesPushedInCycle: 512,
        bytesPulledInCycle: 1024,
        wasSkipped: false,
        wasCancelled: false,
        error: Exception('Test Error'), // This field is not serialized
      );

      test('correctly serializes to a map', () {
        final map = originalResult.toMap();

        expect(map['userId'], 'user-123');
        expect(map['duration'], 5000);
        expect(map['syncedCount'], 10);
        expect(map['failedCount'], 2);
        expect(map['conflictsResolved'], 1);
        expect(map['totalBytesPushed'], 2048);
        expect(map['totalBytesPulled'], 4096);
        expect(map['bytesPushedInCycle'], 512);
        expect(map['bytesPulledInCycle'], 1024);
        expect(map['wasSkipped'], isFalse);
        expect(map['wasCancelled'], isFalse);
        expect(map.containsKey('pendingOperations'), isFalse);
        expect(map.containsKey('error'), isFalse);
      });

      test('correctly deserializes from a map', () {
        final map = originalResult.toMap();
        final deserializedResult = DatumSyncResult<TestEntity>.fromMap(map);

        // Compare properties that are expected to be serialized
        expect(deserializedResult.userId, originalResult.userId);
        expect(deserializedResult.duration, originalResult.duration);
        expect(deserializedResult.syncedCount, originalResult.syncedCount);
        expect(deserializedResult.failedCount, originalResult.failedCount);
        expect(deserializedResult.conflictsResolved, originalResult.conflictsResolved);
        expect(deserializedResult.totalBytesPushed, originalResult.totalBytesPushed);
        expect(deserializedResult.totalBytesPulled, originalResult.totalBytesPulled);
        expect(deserializedResult.bytesPushedInCycle, originalResult.bytesPushedInCycle);
        expect(deserializedResult.bytesPulledInCycle, originalResult.bytesPulledInCycle);
        expect(deserializedResult.wasSkipped, originalResult.wasSkipped);
        expect(deserializedResult.wasCancelled, originalResult.wasCancelled);

        // Verify non-serialized fields have default values
        expect(deserializedResult.pendingOperations, isEmpty);
        expect(deserializedResult.error, isNull);
      });
    });
  });
}
