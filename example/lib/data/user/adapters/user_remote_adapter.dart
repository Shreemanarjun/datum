// ignore_for_file: public_member_api_docs, sort_constructors_first

import 'dart:async';

import 'package:datum/datum.dart';
import 'package:example/custom_connectivity_checker.dart';
import 'package:example/data/user/entity/user.dart';

class UserRemoteAdapter extends RemoteAdapter<User> {
  final Map<String, Map<String, User>> _remoteStorage = {};
  final Map<String, DatumSyncMetadata?> _remoteMetadata = {};
  final _changeController =
      StreamController<DatumChangeDetail<User>>.broadcast();

  @override
  Stream<DatumChangeDetail<User>>? get changeStream => _changeController.stream;

  @override
  Future<void> create(User entity) {
    _remoteStorage.putIfAbsent(entity.userId, () => {})[entity.id] = entity;
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
  Future<void> delete(String id, {String? userId}) {
    final item = _remoteStorage[userId ?? '']?.remove(id);
    if (item != null) {
      _changeController.add(
        DatumChangeDetail(
          entityId: id,
          userId: userId ?? '',
          type: DatumOperationType.delete,
          timestamp: DateTime.now(),
        ),
      );
    }
    return Future.value();
  }

  @override
  Future<DatumSyncMetadata?> getSyncMetadata(String userId) {
    return Future.value(_remoteMetadata[userId]);
  }

  @override
  Future<void> initialize() {
    // No-op for in-memory adapter
    return Future.value();
  }

  @override
  Future<bool> isConnected() {
    return CustomConnectivityChecker().isConnected;
  }

  @override
  Future<User> patch({
    required String id,
    required Map<String, dynamic> delta,
    String? userId,
  }) {
    final existing = _remoteStorage[userId ?? '']?[id];
    if (existing == null) {
      throw EntityNotFoundException(
        'Entity with id $id not found for user ${userId ?? ''} on remote.',
      );
    }

    final json = existing.toDatumMap()..addAll(delta);
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
      return Future.value(_remoteStorage[userId]?[id]);
    }
    for (final userStorage in _remoteStorage.values) {
      if (userStorage.containsKey(id)) return Future.value(userStorage[id]);
    }
    return Future.value(null);
  }

  @override
  Future<List<User>> readAll({String? userId, DatumSyncScope? scope}) {
    if (userId != null) {
      return Future.value(_remoteStorage[userId]?.values.toList() ?? []);
    }
    return Future.value(
      _remoteStorage.values.expand((map) => map.values).toList(),
    );
  }

  @override
  Future<void> update(User entity) {
    _remoteStorage.putIfAbsent(entity.userId, () => {})[entity.id] = entity;
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
    _remoteMetadata[userId] = metadata;
    return Future.value();
  }

  @override
  Future<void> dispose() {
    return _changeController.close();
  }
}
