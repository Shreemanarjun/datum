import 'dart:async';

import 'package:datum/datum.dart';
import 'package:example/data/user/entity/user.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

class UserLocalAdapter extends LocalAdapter<UserEntity> {
  // Storing as Map<String, dynamic> to avoid needing a TypeAdapter for User
  late Box<Map> _userBox;
  late Box<List> _pendingOpsBox;
  // Store metadata as Map to avoid requiring a Hive TypeAdapter for DatumSyncMetadata.
  late Box<Map> _metadataBox;

  int _schemaVersion = 0;

  @override
  UserEntity get sampleInstance => UserEntity.fromMap({'id': '', 'userId': ''});

  @override
  Future<void> addPendingOperation(
    String userId,
    DatumSyncOperation<UserEntity> operation,
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
  Stream<DatumChangeDetail<UserEntity>>? changeStream() {
    return _userBox.watch().map((event) {
      final userMap = event.value;
      final user =
          userMap != null ? UserEntity.fromMap(_normalizeMap(userMap)) : null;
      return DatumChangeDetail(
        entityId: event.key as String,
        userId: user?.userId ?? '',
        type: event.deleted
            ? DatumOperationType.delete
            : DatumOperationType.update,
        timestamp: DateTime.now(),
        data: user,
      );
    });
  }

  @override
  Future<void> clear() {
    return _userBox.clear();
  }

  @override
  Future<void> clearUserData(String userId) {
    final userKeys = _userBox.values
        .where((map) => map['userId'] == userId)
        .map((map) => map['id'] as String);

    return Future.wait([
      _userBox.deleteAll(userKeys),
      _pendingOpsBox.delete(userId),
      _metadataBox.delete(userId),
    ]);
  }

  @override
  Future<void> create(UserEntity entity) {
    return _userBox.put(entity.id, entity.toDatumMap(target: MapTarget.local));
  }

  @override
  Future<bool> delete(String id, {String? userId}) {
    // Hive's delete doesn't tell us if it was successful, but we can check first.
    if (_userBox.containsKey(id)) {
      return _userBox.delete(id).then((_) => true);
    }
    return Future.value(false);
  }

  @override
  Future<void> dispose() {
    // In a real app, you might not close boxes here if they are used elsewhere.
    // For this example, we assume the adapter owns the boxes.
    return Future.wait([
      _userBox.close(),
      _pendingOpsBox.close(),
      _metadataBox.close(),
    ]);
  }

  @override
  Future<List<Map<String, dynamic>>> getAllRawData({String? userId}) {
    final maps = _userBox.values
        .where((map) => userId == null || map['userId'] == userId);
    return Future.value(maps.map((e) => _normalizeMap(e)).toList());
  }

  @override
  Future<List<String>> getAllUserIds() {
    // Get all unique userIds from the stored users.
    final userIds = _userBox.values
        .map((map) => _normalizeMap(map)['userId'] as String)
        .toSet()
        .toList();
    return Future.value(userIds);
  }

  @override
  Future<List<DatumSyncOperation<UserEntity>>> getPendingOperations(
      String userId) {
    final opsList = _pendingOpsBox.get(userId);
    if (opsList == null) {
      return Future.value([]);
    }
    final ops = opsList.cast<Map>().map((raw) {
      final m =
          _normalizeMap(raw); // This correctly creates a Map<String, dynamic>
      return DatumSyncOperation.fromMap(
          m, UserEntity.fromMap); // Use the normalized map 'm' here
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
  Future<void> initialize() {
    return Future.wait([
      Hive.openBox<Map>('users').then((box) => _userBox = box),
      Hive.openBox<List>('pending_user_ops')
          .then((box) => _pendingOpsBox = box),
      // Open metadata box as Map to avoid needing a registered adapter.
      Hive.openBox<Map>('user_metadata').then((box) => _metadataBox = box),
    ]);
  }

  @override
  Future<void> overwriteAllRawData(
    List<Map<String, dynamic>> data, {
    String? userId,
  }) {
    clear();
    for (final rawItem in data) {
      final user = UserEntity.fromMap(rawItem);
      create(user);
    }
    return Future.value();
  }

  @override
  Future<UserEntity> patch({
    required String id,
    required Map<String, dynamic> delta,
    String? userId,
  }) {
    final existing = _userBox.get(id);
    if (existing == null) {
      throw Exception('Entity with id $id not found for user ${userId ?? ''}.');
    }

    final json = UserEntity.fromMap(_normalizeMap(existing))
        .toDatumMap(target: MapTarget.local)
      ..addAll(delta);
    final patchedItem = UserEntity.fromMap(json);
    update(patchedItem);
    return Future.value(patchedItem);
  }

  @override
  Future<List<UserEntity>> query(DatumQuery query, {String? userId}) {
    // This is a simplified query for an in-memory adapter.
    // A real implementation would parse the query object.
    return readAll(userId: userId);
  }

  @override
  Future<UserEntity?> read(String id, {String? userId}) {
    final userMap = _userBox.get(id);
    if (userMap == null) return Future.value(null);
    final user = UserEntity.fromMap(_normalizeMap(userMap));
    // If a userId is provided, ensure the found user matches.
    if (userId == null || user.userId == userId) {
      return Future.value(user);
    }
    return Future.value(null);
  }

  @override
  Future<List<UserEntity>> readAll({String? userId}) {
    final maps = _userBox.values
        .where((map) => userId == null || map['userId'] == userId);
    return Future.value(
        maps.map((map) => UserEntity.fromMap(_normalizeMap(map))).toList());
  }

  @override
  Future<PaginatedResult<UserEntity>> readAllPaginated(
    PaginationConfig config, {
    String? userId,
  }) {
    throw UnimplementedError(
      'readAllPaginated is not implemented for this example.',
    );
  }

  @override
  Future<Map<String, UserEntity>> readByIds(
    List<String> ids, {
    required String userId,
  }) {
    final userMaps = _userBox.values.where((map) => map['userId'] == userId);
    final results = <String, UserEntity>{};
    for (final id in ids) {
      final userMap =
          userMaps.firstWhere((map) => map['id'] == id, orElse: () => {});
      if (userMap.isNotEmpty) {
        results[id] = UserEntity.fromMap(_normalizeMap(userMap));
      }
    }
    return Future.value(results);
  }

  @override
  Future<void> removePendingOperation(String operationId) {
    // This is more efficient as it avoids iterating over every user's pending ops.
    // It assumes the operationId contains enough info to find the user,
    // or that we find the first user with that op.
    // For this example, we'll iterate, but in a cleaner way.
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
      // In a real DB with transactions, you would roll back here.
      // For Hive, we rethrow to signal the failure.
      rethrow;
    }
  }

  @override
  Future<void> update(UserEntity entity) {
    return _userBox.put(entity.id, entity.toDatumMap(target: MapTarget.local));
  }

  @override
  Future<void> updateSyncMetadata(DatumSyncMetadata metadata, String userId) {
    return _metadataBox.put(userId, metadata.toMap());
  }

  @override
  Stream<List<UserEntity>>? watchAll(
      {String? userId, bool? includeInitialData}) {
    // Use box.watch() for efficient reactive queries.
    // We use a transformer to combine the initial data with subsequent changes.
    final changes = _userBox.watch().asyncMap((_) => readAll(userId: userId));

    return changes.transform(
      StreamTransformer.fromBind((stream) async* {
        // 1. Yield the initial data first, if requested.
        if (includeInitialData ?? true) {
          yield await readAll(userId: userId);
        }
        // 2. Then, yield all subsequent updates from the stream.
        yield* stream;
      }),
    );
  }

  @override
  Stream<UserEntity?>? watchById(String id, {String? userId}) {
    // Watch for changes only to the specific key (id).
    final changes = _userBox.watch(key: id).asyncMap((event) async {
      // After a change, re-read the item to ensure we get the correct state.
      return read(id, userId: userId);
    });

    return changes.transform(StreamTransformer.fromBind((stream) async* {
      // 1. Yield the initial state of the item.
      yield await read(id, userId: userId);
      // 2. Then, yield all subsequent updates.
      yield* stream;
    }));
  }

  // Normalize a Map<dynamic, dynamic> (from Hive) into Map<String, dynamic>.
  Map<String, dynamic> _normalizeMap(dynamic maybeMap) {
    if (maybeMap == null) return <String, dynamic>{};
    if (maybeMap is Map) {
      final out = <String, dynamic>{};
      maybeMap.forEach((k, v) {
        final key = k == null ? '' : k.toString();
        if (v is Map) {
          out[key] = _normalizeMap(v); // Recurse for nested maps
        } else if (v is List) {
          // Also handle lists of maps
          out[key] = v.map(_normalizeMap).toList();
        } else {
          out[key] = v;
        }
      });
      return out;
    }
    return <String, dynamic>{};
  }
}
