import 'dart:async';

import 'package:datum/datum.dart';
import 'package:example/data/user/entity/user.dart';

class UserLocalAdapter extends LocalAdapter<User> {
  final Map<String, Map<String, User>> _storage = {};
  final Map<String, List<DatumSyncOperation<User>>> _pendingOps = {};
  final Map<String, DatumSyncMetadata?> _metadata = {};
  final _changeController =
      StreamController<DatumChangeDetail<User>>.broadcast();
  int _schemaVersion = 0;

  @override
  User get sampleInstance => User.fromMap({'id': '', 'userId': ''}); // Dummy instance for reflection

  @override
  Future<void> addPendingOperation(
    String userId,
    DatumSyncOperation<User> operation,
  ) {
    final userOps = _pendingOps.putIfAbsent(userId, () => []);
    final existingIndex = userOps.indexWhere((op) => op.id == operation.id);
    if (existingIndex != -1) {
      userOps[existingIndex] = operation;
    } else {
      userOps.add(operation);
    }
    return Future.value();
  }

  @override
  Stream<DatumChangeDetail<User>>? changeStream() {
    return _changeController.stream;
  }

  @override
  Future<void> clear() {
    _storage.clear();
    _pendingOps.clear();
    _metadata.clear();
    return Future.value();
  }

  @override
  Future<void> clearUserData(String userId) {
    _storage.remove(userId);
    _pendingOps.remove(userId);
    _metadata.remove(userId);
    return Future.value();
  }

  @override
  Future<void> create(User entity) {
    _storage.putIfAbsent(entity.userId, () => {})[entity.id] = entity;
    _changeController.add(
      DatumChangeDetail(
        entityId: entity.id,
        userId: entity.userId,
        type: DatumOperationType.create,
        timestamp: DateTime.now(),
        data: entity,
      ),
    );
    return Future.value();
  }

  @override
  Future<bool> delete(String id, {String? userId}) {
    final item = _storage[userId ?? '']?.remove(id);
    if (item != null) {
      _changeController.add(
        DatumChangeDetail(
          entityId: id,
          userId: userId ?? '',
          type: DatumOperationType.delete,
          timestamp: DateTime.now(),
        ),
      );
      return Future.value(true);
    }
    return Future.value(false);
  }

  @override
  Future<void> dispose() {
    return _changeController.close();
  }

  @override
  Future<List<Map<String, dynamic>>> getAllRawData({String? userId}) {
    return Future.value(
      _storage.values
          .expand((map) => map.values)
          .map((e) => e.toMap())
          .toList(),
    );
  }

  @override
  Future<List<String>> getAllUserIds() {
    return Future.value(_storage.keys.toList());
  }

  @override
  Future<List<DatumSyncOperation<User>>> getPendingOperations(String userId) {
    return Future.value(List.from(_pendingOps[userId] ?? []));
  }

  @override
  Future<int> getStoredSchemaVersion() {
    return Future.value(_schemaVersion);
  }

  @override
  Future<DatumSyncMetadata?> getSyncMetadata(String userId) {
    return Future.value(_metadata[userId]);
  }

  @override
  Future<void> initialize() {
    // No-op for in-memory adapter
    return Future.value();
  }

  @override
  Future<void> overwriteAllRawData(
    List<Map<String, dynamic>> data, {
    String? userId,
  }) {
    clear();
    for (final rawItem in data) {
      final user = User.fromMap(rawItem);
      create(user);
    }
    return Future.value();
  }

  @override
  Future<User> patch({
    required String id,
    required Map<String, dynamic> delta,
    String? userId,
  }) {
    final existing = _storage[userId ?? '']?[id];
    if (existing == null) {
      throw Exception('Entity with id $id not found for user ${userId ?? ''}.');
    }

    final json = existing.toMap()..addAll(delta);
    final patchedItem = User.fromMap(json);
    update(patchedItem);
    return Future.value(patchedItem);
  }

  @override
  Future<List<User>> query(DatumQuery query, {String? userId}) {
    // This is a simplified query for an in-memory adapter.
    // A real implementation would parse the query object.
    return readAll(userId: userId);
  }

  @override
  Future<User?> read(String id, {String? userId}) {
    if (userId != null) {
      return Future.value(_storage[userId]?[id]);
    }
    for (final userStorage in _storage.values) {
      if (userStorage.containsKey(id)) return Future.value(userStorage[id]);
    }
    return Future.value(null);
  }

  @override
  Future<List<User>> readAll({String? userId}) {
    if (userId != null) {
      return Future.value(_storage[userId]?.values.toList() ?? []);
    }
    return Future.value(_storage.values.expand((map) => map.values).toList());
  }

  @override
  Future<PaginatedResult<User>> readAllPaginated(
    PaginationConfig config, {
    String? userId,
  }) {
    throw UnimplementedError(
      'readAllPaginated is not implemented for this example.',
    );
  }

  @override
  Future<Map<String, User>> readByIds(
    List<String> ids, {
    required String userId,
  }) {
    final userStorage = _storage[userId];
    if (userStorage == null) return Future.value({});

    final results = <String, User>{};
    for (final id in ids) {
      if (userStorage.containsKey(id)) results[id] = userStorage[id]!;
    }
    return Future.value(results);
  }

  @override
  Future<void> removePendingOperation(String operationId) {
    for (final ops in _pendingOps.values) {
      ops.removeWhere((op) => op.id == operationId);
    }
    return Future.value();
  }

  @override
  Future<void> setStoredSchemaVersion(int version) {
    _schemaVersion = version;
    return Future.value();
  }

  @override
  Future<R> transaction<R>(Future<R> Function() action) {
    // In-memory doesn't have real transactions, but we can simulate it for API compatibility.
    return action();
  }

  @override
  Future<void> update(User entity) {
    _storage.putIfAbsent(entity.userId, () => {})[entity.id] = entity;
    _changeController.add(
      DatumChangeDetail(
        entityId: entity.id,
        userId: entity.userId,
        type: DatumOperationType.update,
        timestamp: DateTime.now(),
        data: entity,
      ),
    );
    return Future.value();
  }

  @override
  Future<void> updateSyncMetadata(DatumSyncMetadata metadata, String userId) {
    _metadata[userId] = metadata;
    return Future.value();
  }
}
