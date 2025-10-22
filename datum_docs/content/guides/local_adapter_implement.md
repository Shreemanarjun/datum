---
title: Local Adapter Implementation
---


Datum uses adapters to interact with your local storage (e.g., SQLite, Hive) and remote backend (e.g., REST API, GraphQL). You need to implement `LocalAdapter` and `RemoteAdapter` for each `DatumEntity` you define.

These examples are simplified; your actual implementations will contain logic for data persistence and network communication.

## Define you local adapter


```dart

import 'dart:async';

import 'package:datum/datum.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

class TaskLocalAdapter extends LocalAdapter<Task> {

  @override
  Task get sampleInstance => Task.fromMap({'id': '', 'userId': ''});

  @override
  Future<void> addPendingOperation(
    String userId,
    DatumSyncOperation<Task> operation,
  ) {}

  @override
  Stream<DatumChangeDetail<Task>>? changeStream() {}

  @override
  Future<void> clear() {}

  @override
  Future<void> clearUserData(String userId) {}

  @override
  Future<void> create(Task entity) {}

  @override
  Future<bool> delete(String id, {String? userId}) {}

  @override
  Future<void> dispose() { }

  @override
  Future<List<Map<String, dynamic>>> getAllRawData({String? userId}) {}

  @override
  Future<List<String>> getAllUserIds() {}

  @override
  Future<List<DatumSyncOperation<Task>>> getPendingOperations(String userId) { }

  @override
  Future<int> getStoredSchemaVersion() { }

  @override
  Future<DatumSyncMetadata?> getSyncMetadata(String userId) {}

  @override
  Future<DatumSyncResult<Task>?> getLastSyncResult(String userId) async { }

  @override
  Future<void> saveLastSyncResult(String userId, DatumSyncResult<Task> result) { }

  @override
  Future<void> initialize() { }

  @override
  Future<void> overwriteAllRawData(
    List<Map<String, dynamic>> data, {
    String? userId,
  }) { }

  @override
  Future<Task> patch({
    required String id,
    required Map<String, dynamic> delta,
    String? userId,
  }) { }

  @override
  Future<List<Task>> query(DatumQuery query, {String? userId}) {}

  @override
  Future<Task?> read(String id, {String? userId}) { }

  @override
  Future<List<Task>> readAll({String? userId}) { }

  @override
  Future<PaginatedResult<Task>> readAllPaginated(
    PaginationConfig config, {
    String? userId,
  }) { }

  @override
  Future<Map<String, Task>> readByIds(
    List<String> ids, {
    required String userId,
  }) { }

  @override
  Future<void> removePendingOperation(String operationId) {  }

  @override
  Future<void> setStoredSchemaVersion(int version) {  }

  @override
  Future<R> transaction<R>(Future<R> Function() action) { }

  @override
  Future<void> update(Task entity) { }

  @override
  Future<void> updateSyncMetadata(DatumSyncMetadata metadata, String userId) { }

  @override
  Stream<List<Task>>? watchAll(
      {String? userId, bool includeInitialData = true}) { }

  @override
  Stream<Task?>? watchById(String id, {String? userId}) {}

  Map<String, dynamic> _normalizeMap(dynamic maybeMap) { }

  @override
  Future<int> getStorageSize({String? userId}) async { }

  @override
  Future<AdapterHealthStatus> checkHealth() async {}

```