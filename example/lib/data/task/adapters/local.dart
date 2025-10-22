import 'dart:async';

import 'package:datum/datum.dart';
import 'package:example/data/task/entity/task.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

class TaskLocalAdapter extends LocalAdapter<Task> {
  late Box<Map> _taskBox;
  late Box<List> _pendingOpsBox;
  late Box<Map> _metadataBox;

  int _schemaVersion = 0;

  @override
  Task get sampleInstance => Task.fromMap({'id': '', 'userId': ''});

  @override
  Future<void> addPendingOperation(
    String userId,
    DatumSyncOperation<Task> operation,
  ) {
    final opsList = (_pendingOpsBox.get(userId) ?? []).cast<Map>().toList();
    final existingIndex =
        opsList.indexWhere((map) => map['id'] == operation.id);

    if (existingIndex != -1) {
      opsList[existingIndex] = operation.toMap();
    } else {
      opsList.add(operation.toMap());
    }
    return _pendingOpsBox.put(userId, opsList);
  }

  @override
  Stream<DatumChangeDetail<Task>>? changeStream() {
    return _taskBox.watch().map((event) {
      final taskMap = event.value;
      final task =
          taskMap != null ? Task.fromMap(_normalizeMap(taskMap)) : null;
      return DatumChangeDetail(
        entityId: event.key as String,
        userId: task?.userId ?? '',
        type: event.deleted
            ? DatumOperationType.delete
            : DatumOperationType.update,
        timestamp: DateTime.now(),
        data: task,
      );
    });
  }

  @override
  Future<void> clear() {
    return _taskBox.clear();
  }

  @override
  Future<void> clearUserData(String userId) {
    final taskKeys = _taskBox.values
        .where((map) => map['userId'] == userId)
        .map((map) => map['id'] as String);

    return Future.wait([
      _taskBox.deleteAll(taskKeys),
      _pendingOpsBox.delete(userId),
      _metadataBox.delete(userId),
    ]);
  }

  @override
  Future<void> create(Task entity) {
    return _taskBox.put(entity.id, entity.toDatumMap(target: MapTarget.local));
  }

  @override
  Future<bool> delete(String id, {String? userId}) {
    if (_taskBox.containsKey(id)) {
      return _taskBox.delete(id).then((_) => true);
    }
    return Future.value(false);
  }

  @override
  Future<void> dispose() {
    return Future.wait([
      _taskBox.close(),
      _pendingOpsBox.close(),
      _metadataBox.close(),
    ]);
  }

  @override
  Future<List<Map<String, dynamic>>> getAllRawData({String? userId}) {
    final maps = _taskBox.values
        .where((map) => userId == null || map['userId'] == userId);
    return Future.value(maps.map((e) => _normalizeMap(e)).toList());
  }

  @override
  Future<List<String>> getAllUserIds() {
    final userIds = _taskBox.values
        .map((map) => _normalizeMap(map)['userId'] as String)
        .toSet()
        .toList();
    return Future.value(userIds);
  }

  @override
  Future<List<DatumSyncOperation<Task>>> getPendingOperations(String userId) {
    final opsList = _pendingOpsBox.get(userId);
    if (opsList == null) {
      return Future.value([]);
    }
    final ops = opsList.cast<Map>().map((raw) {
      final m = _normalizeMap(raw);
      return DatumSyncOperation.fromMap(m, Task.fromMap);
    }).toList();
    return Future.value(ops);
  }

  @override
  Future<int> getStoredSchemaVersion() {
    return Future.value(_schemaVersion);
  }

  @override
  Future<DatumSyncMetadata?> getSyncMetadata(String userId) {
    final map = _metadataBox.get(userId);
    if (map == null) return Future.value(null);
    final m = _normalizeMap(map);
    return Future.value(DatumSyncMetadata(
      userId: m['userId'] as String? ?? userId,
      dataHash: m['dataHash'] as String? ?? '',
    ));
  }

  @override
  Future<DatumSyncResult<Task>?> getLastSyncResult(String userId) async {
    final map = _metadataBox.get('last_sync_result_$userId');
    if (map == null) return null;
    return DatumSyncResult.fromMap(_normalizeMap(map));
  }

  @override
  Future<void> saveLastSyncResult(String userId, DatumSyncResult<Task> result) {
    return _metadataBox.put(
      'last_sync_result_$userId',
      result.toMap(),
    );
  }

  @override
  Future<void> initialize() {
    return Future.wait([
      Hive.openBox<Map>('tasks').then((box) => _taskBox = box),
      Hive.openBox<List>('pending_task_ops')
          .then((box) => _pendingOpsBox = box),
      Hive.openBox<Map>('task_metadata').then((box) => _metadataBox = box),
    ]);
  }

  @override
  Future<void> overwriteAllRawData(
    List<Map<String, dynamic>> data, {
    String? userId,
  }) {
    clear();
    for (final rawItem in data) {
      final task = Task.fromMap(rawItem);
      create(task);
    }
    return Future.value();
  }

  @override
  Future<Task> patch({
    required String id,
    required Map<String, dynamic> delta,
    String? userId,
  }) {
    final existing = _taskBox.get(id);
    if (existing == null) {
      throw Exception('Entity with id $id not found for user ${userId ?? ''}.');
    }

    // Create a new map from the existing entity's data.
    final json = Map<String, dynamic>.from(Task.fromMap(_normalizeMap(existing))
        .toDatumMap(target: MapTarget.local));
    json.addAll(delta); // Apply the changes from the delta.
    final patchedItem = Task.fromMap(json);
    update(patchedItem);
    return Future.value(patchedItem);
  }

  @override
  Future<List<Task>> query(DatumQuery query, {String? userId}) {
    return readAll(userId: userId);
  }

  @override
  Future<Task?> read(String id, {String? userId}) {
    final taskMap = _taskBox.get(id);
    if (taskMap == null) return Future.value(null);
    final task = Task.fromMap(_normalizeMap(taskMap));
    if (userId == null || task.userId == userId) {
      return Future.value(task);
    }
    return Future.value(null);
  }

  @override
  Future<List<Task>> readAll({String? userId}) {
    final maps = _taskBox.values
        .where((map) => userId == null || map['userId'] == userId);
    return Future.value(
        maps.map((map) => Task.fromMap(_normalizeMap(map))).toList());
  }

  @override
  Future<PaginatedResult<Task>> readAllPaginated(
    PaginationConfig config, {
    String? userId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, Task>> readByIds(
    List<String> ids, {
    required String userId,
  }) {
    final taskMaps = _taskBox.values.where((map) => map['userId'] == userId);
    final results = <String, Task>{};
    for (final id in ids) {
      final taskMap =
          taskMaps.firstWhere((map) => map['id'] == id, orElse: () => {});
      if (taskMap.isNotEmpty) {
        results[id] = Task.fromMap(_normalizeMap(taskMap));
      }
    }
    return Future.value(results);
  }

  @override
  Future<void> removePendingOperation(String operationId) {
    for (final userId in _pendingOpsBox.keys) {
      final ops = (_pendingOpsBox.get(userId))?.toList();
      if (ops == null) continue;

      final initialLength = ops.length;
      ops.removeWhere((op) => (op as Map)['id'] == operationId);

      if (ops.length < initialLength) _pendingOpsBox.put(userId, ops);
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
    try {
      return action();
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<void> update(Task entity) {
    return _taskBox.put(entity.id, entity.toDatumMap(target: MapTarget.local));
  }

  @override
  Future<void> updateSyncMetadata(DatumSyncMetadata metadata, String userId) {
    return _metadataBox.put(userId, metadata.toMap());
  }

  @override
  Stream<List<Task>>? watchAll(
      {String? userId, bool includeInitialData = true}) {
    final changes = _taskBox.watch().asyncMap((_) => readAll(userId: userId));

    return changes.transform(
      StreamTransformer.fromBind((stream) async* {
        // 1. Yield the initial data first, if requested.
        if (includeInitialData) {
          yield await readAll(userId: userId);
        }
        // 2. Then, yield all subsequent updates from the stream.
        yield* stream;
      }),
    );
  }

  @override
  Stream<Task?>? watchById(String id, {String? userId}) {
    final changes = _taskBox.watch(key: id).asyncMap((event) async {
      return read(id, userId: userId);
    });

    return changes.transform(StreamTransformer.fromBind((stream) async* {
      yield await read(id, userId: userId);
      yield* stream;
    }));
  }

  Map<String, dynamic> _normalizeMap(dynamic maybeMap) {
    if (maybeMap == null) return <String, dynamic>{};
    if (maybeMap is Map) {
      final out = <String, dynamic>{};
      maybeMap.forEach((k, v) {
        final key = k == null ? '' : k.toString();
        if (v is Map) {
          out[key] = _normalizeMap(v);
        } else if (v is List) {
          out[key] = v.map(_normalizeMap).toList();
        } else {
          out[key] = v;
        }
      });
      return out;
    }
    return <String, dynamic>{};
  }

  @override
  Future<int> getStorageSize({String? userId}) async {
    if (!_taskBox.isOpen) return 0;
    // This is a simplified calculation. A real implementation might be more
    // complex depending on the storage engine.
    final allData = await getAllRawData(userId: userId);
    // Offload JSON encoding to an isolate to prevent UI jank.
    return (await const IsolateHelper().computeJsonEncode(allData)).length;
  }

  @override
  Future<AdapterHealthStatus> checkHealth() async {
    return _taskBox.isOpen
        ? AdapterHealthStatus.healthy
        : AdapterHealthStatus.unhealthy;
  }
}
