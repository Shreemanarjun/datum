---
title: Remote Adapter Implementation
---
```dart


import 'dart:async';

import 'package:datum/datum.dart';
import 'package:example/custom_connectivity_checker.dart';
import 'package:example/data/user/entity/user.dart';

class UserRemoteAdapter extends RemoteAdapter<UserEntity> {

  final _changeController =
      StreamController<DatumChangeDetail<UserEntity>>.broadcast();

  @override
  Stream<DatumChangeDetail<UserEntity>>? get changeStream =>
      _changeController.stream;

  @override
  Future<void> create(UserEntity entity) { }

  @override
  Future<void> delete(String id, {String? userId}) {}

  @override
  Future<DatumSyncMetadata?> getSyncMetadata(String userId) { }

  @override
  Future<void> initialize() { }

  @override
  Future<bool> isConnected() {}

  @override
  Future<UserEntity> patch({
    required String id,
    required Map<String, dynamic> delta,
    String? userId,
  }) { }

  @override
  Future<List<UserEntity>> query(DatumQuery query, {String? userId}) {}

  @override
  Future<UserEntity?> read(String id, {String? userId}) { }

  @override
  Future<List<UserEntity>> readAll({String? userId, DatumSyncScope? scope}) {}

  @override
  Future<void> update(UserEntity entity) {}

  @override
  Future<void> updateSyncMetadata(DatumSyncMetadata metadata, String userId) {}

  @override
  Future<void> dispose() {}
}



```