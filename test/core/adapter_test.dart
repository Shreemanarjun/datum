import 'package:datum/datum.dart';
import 'package:flutter_test/flutter_test.dart';

import '../mocks/test_entity.dart';

/// A minimal concrete implementation of [LocalAdapter] for testing default behaviors.
class _TestLocalAdapter extends LocalAdapter<TestEntity> {
  @override
  Future<void> addPendingOperation(
    String userId,
    DatumSyncOperation<TestEntity> operation,
  ) => throw UnimplementedError();
  @override
  Stream<DatumChangeDetail<TestEntity>>? changeStream() =>
      throw UnimplementedError();
  @override
  Future<void> clear() => throw UnimplementedError();
  @override
  Future<void> clearUserData(String userId) => throw UnimplementedError();
  @override
  Future<void> create(TestEntity entity) => throw UnimplementedError();
  @override
  Future<bool> delete(String id, {String? userId}) =>
      throw UnimplementedError();
  @override
  Future<void> dispose() => throw UnimplementedError();
  @override
  Future<List<String>> getAllUserIds() => throw UnimplementedError();
  @override
  Future<List<Map<String, dynamic>>> getAllRawData({String? userId}) =>
      throw UnimplementedError();
  @override
  Future<List<DatumSyncOperation<TestEntity>>> getPendingOperations(
    String userId,
  ) => throw UnimplementedError();
  @override
  Future<int> getStoredSchemaVersion() => throw UnimplementedError();
  @override
  Future<DatumSyncMetadata?> getSyncMetadata(String userId) =>
      throw UnimplementedError();
  @override
  Future<void> initialize() => throw UnimplementedError();
  @override
  Future<void> overwriteAllRawData(
    List<Map<String, dynamic>> data, {
    String? userId,
  }) => throw UnimplementedError();
  @override
  Future<TestEntity> patch({
    required String id,
    required Map<String, dynamic> delta,
    String? userId,
  }) => throw UnimplementedError();
  @override
  Future<List<TestEntity>> query(DatumQuery query, {String? userId}) =>
      throw UnimplementedError();
  @override
  Future<TestEntity?> read(String id, {String? userId}) =>
      throw UnimplementedError();
  @override
  Future<List<TestEntity>> readAll({String? userId}) =>
      throw UnimplementedError();
  @override
  Future<PaginatedResult<TestEntity>> readAllPaginated(
    PaginationConfig config, {
    String? userId,
  }) => throw UnimplementedError();
  @override
  Future<Map<String, TestEntity>> readByIds(
    List<String> ids, {
    required String userId,
  }) => throw UnimplementedError();
  @override
  Future<void> removePendingOperation(String operationId) =>
      throw UnimplementedError();
  @override
  Future<void> setStoredSchemaVersion(int version) =>
      throw UnimplementedError();
  @override
  Future<R> transaction<R>(Future<R> Function() action) =>
      throw UnimplementedError();
  @override
  Future<void> update(TestEntity entity) => throw UnimplementedError();
  @override
  Future<void> updateSyncMetadata(DatumSyncMetadata metadata, String userId) =>
      throw UnimplementedError();
}

/// A minimal concrete implementation of [RemoteAdapter] for testing default behaviors.
class _TestRemoteAdapter extends RemoteAdapter<TestEntity> {
  @override
  Future<void> create(TestEntity entity) => throw UnimplementedError();
  @override
  Future<void> delete(String id, {String? userId}) =>
      throw UnimplementedError();
  @override
  Stream<DatumChangeDetail<TestEntity>>? get changeStream =>
      throw UnimplementedError();
  @override
  Future<DatumSyncMetadata?> getSyncMetadata(String userId) =>
      throw UnimplementedError();
  @override
  Future<void> initialize() => throw UnimplementedError();
  @override
  Future<bool> isConnected() => throw UnimplementedError();
  @override
  Future<TestEntity> patch({
    required String id,
    required Map<String, dynamic> delta,
    String? userId,
  }) => throw UnimplementedError();
  @override
  Future<List<TestEntity>> query(DatumQuery query, {String? userId}) =>
      throw UnimplementedError();
  @override
  Future<TestEntity?> read(String id, {String? userId}) =>
      throw UnimplementedError();
  @override
  Future<List<TestEntity>> readAll({String? userId, DatumSyncScope? scope}) =>
      throw UnimplementedError();
  @override
  Future<void> update(TestEntity entity) => throw UnimplementedError();
  @override
  Future<void> updateSyncMetadata(DatumSyncMetadata metadata, String userId) =>
      throw UnimplementedError();
}

void main() {
  group('LocalAdapter', () {
    final adapter = _TestLocalAdapter();

    test('name property returns the runtime type', () {
      expect(adapter.name, '_TestLocalAdapter');
    });

    test('default stream implementations return null', () {
      expect(adapter.schemaVersionStream(), isNull);
      expect(adapter.watchAll(), isNull);
      expect(adapter.watchById('1'), isNull);
      expect(
        adapter.watchAllPaginated(const PaginationConfig(pageSize: 10)),
        isNull,
      );
      expect(adapter.watchQuery(const DatumQuery()), isNull);
      expect(adapter.watchCount(), isNull);
      expect(adapter.watchFirst(), isNull);
    });
  });

  group('RemoteAdapter', () {
    final adapter = _TestRemoteAdapter();

    test('name property returns the runtime type', () {
      expect(adapter.name, '_TestRemoteAdapter');
    });

    test('default stream implementations return null', () {
      expect(adapter.watchAll(), isNull);
      expect(adapter.watchById('1'), isNull);
      expect(adapter.watchQuery(const DatumQuery()), isNull);
    });

    test('default dispose method completes successfully', () {
      expect(adapter.dispose(), completes);
    });
  });
}
