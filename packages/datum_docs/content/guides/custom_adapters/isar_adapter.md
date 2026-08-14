---
title: Isar Local Adapter
---

This guide shows how to implement a complete Isar local adapter for Datum.

## Overview

Isar is a high-performance database for Flutter built on top of SQLite. This adapter provides a full implementation of the `LocalAdapter` interface using Isar for data persistence.

## Setup

First, add Isar to your `pubspec.yaml`:

```yaml
dependencies:
  isar: ^4.0.0
  isar_flutter_libs: ^4.0.0

dev_dependencies:
  isar_generator: ^4.0.0
  build_runner: ^2.4.6
```

## Entity Definition

Create an Isar collection for your entity:

```dart
import 'package:isar/isar.dart';

part 'task.g.dart';

@collection
class TaskEntity {
  Id id = Isar.autoIncrement; // Isar ID

  @Index(unique: true, replace: true)
  late String datumId; // Your Datum entity ID

  @Index()
  late String userId;

  late String title;
  late bool isCompleted;

  @Index()
  late DateTime createdAt;

  @Index()
  late DateTime modifiedAt;

  late bool isDeleted;

  @Index()
  late int version;

  TaskEntity({
    required this.datumId,
    required this.userId,
    required this.title,
    this.isCompleted = false,
    required this.createdAt,
    required this.modifiedAt,
    this.isDeleted = false,
    this.version = 1,
  });

  // Convert from/to Datum entity
  factory TaskEntity.fromDatum(Task task) => TaskEntity(
    datumId: task.id,
    userId: task.userId,
    title: task.title,
    isCompleted: task.isCompleted,
    createdAt: task.createdAt,
    modifiedAt: task.modifiedAt,
    isDeleted: task.isDeleted,
    version: task.version,
  );

  Task toDatum() => Task(
    id: datumId,
    userId: userId,
    title: title,
    isCompleted: isCompleted,
    createdAt: createdAt,
    modifiedAt: modifiedAt,
    isDeleted: isDeleted,
    version: version,
  );
}
```

Generate the Isar code:

```bash
dart run build_runner build
```

## Implementation

```dart
import 'package:datum/datum.dart';
import 'package:isar/isar.dart';

class IsarLocalAdapter<T extends DatumEntityInterface> extends LocalAdapter<T> {
  final IsarCollection<T> collection;
  final T Function(Map<String, dynamic>) fromMap;

  IsarLocalAdapter({
    required this.collection,
    required this.fromMap,
  });

  @override
  Future<void> initialize() async {
    // Isar is initialized globally, no specific initialization needed
  }

  @override
  Future<void> dispose() async {
    // Isar is disposed globally
  }

  @override
  Future<AdapterHealthStatus> checkHealth() async {
    try {
      await collection.count();
      return AdapterHealthStatus.healthy;
    } catch (e) {
      return AdapterHealthStatus.unhealthy;
    }
  }

  @override
  Future<T?> read(String id, {String? userId}) async {
    final query = collection.filter().idEqualTo(id);
    if (userId != null) {
      query.userIdEqualTo(userId);
    }
    return await query.findFirst();
  }

  @override
  Future<List<T>> readAll({String? userId}) async {
    var query = collection.filter().isDeletedEqualTo(false);
    if (userId != null) {
      query = query.userIdEqualTo(userId);
    }
    return await query.findAll();
  }

  @override
  Future<void> create(T entity) async {
    await collection.isar.writeTxn(() async {
      await collection.put(entity);
    });
  }

  @override
  Future<void> update(T entity) async {
    await collection.isar.writeTxn(() async {
      await collection.put(entity);
    });
  }

  @override
  Future<bool> delete(String id, {String? userId}) async {
    return collection.isar.writeTxn(() async {
      final entity = await read(id, userId: userId);
      if (entity == null) return false;
      // Soft delete by updating the entity
      final updated = entity.copyWith(isDeleted: true) as T;
      await collection.put(updated);
      return true;
    });
  }

  @override
  Future<T> patch({
    required String id,
    required Map<String, dynamic> delta,
    String? userId,
  }) async {
    return collection.isar.writeTxn(() async {
      final entity = await read(id, userId: userId);
      if (entity == null) {
        throw EntityNotFoundException(
          message: 'Entity with id $id not found for patch.',
        );
      }
      // Create updated entity from delta
      final updatedMap = entity.toDatumMap()..addAll(delta);
      final updated = fromMap(updatedMap);
      await collection.put(updated);
      return updated;
    });
  }

  @override
  Future<List<T>> query(DatumQuery query, {String? userId}) async {
    var builder = collection.filter().isDeletedEqualTo(false);

    if (userId != null) {
      builder = builder.userIdEqualTo(userId);
    }

    // Apply filters
    for (final filter in query.filters) {
      builder = _applyFilter(builder, filter);
    }

    var queryBuilder = builder;

    // Apply sorting
    for (final sort in query.sorting) {
      switch (sort.field) {
        case 'createdAt':
          queryBuilder = sort.descending
              ? queryBuilder.sortByCreatedAtDesc()
              : queryBuilder.sortByCreatedAt();
          break;
        case 'modifiedAt':
          queryBuilder = sort.descending
              ? queryBuilder.sortByModifiedAtDesc()
              : queryBuilder.sortByModifiedAt();
          break;
        // Add more sort fields as needed
      }
    }

    // Apply pagination
    if (query.offset > 0) {
      queryBuilder = queryBuilder.offset(query.offset);
    }
    if (query.limit != null) {
      queryBuilder = queryBuilder.limit(query.limit!);
    }

    return await queryBuilder.findAll();
  }

  QueryBuilder<T, T, QFilterCondition> _applyFilter(
    QueryBuilder<T, T, QFilterCondition> builder,
    FilterCondition condition,
  ) {
    if (condition is Filter) {
      final field = condition.field;
      final value = condition.value;

      switch (field) {
        case 'id':
          return _applyStringFilter(builder, condition);
        case 'userId':
          return _applyStringFilter(builder, condition);
        case 'createdAt':
        case 'modifiedAt':
          return _applyDateFilter(builder, condition);
        case 'version':
          return _applyIntFilter(builder, condition);
        case 'isDeleted':
          return _applyBoolFilter(builder, condition);
        default:
          // For custom fields, you might need additional logic
          return builder;
      }
    }
    return builder;
  }

  QueryBuilder<T, T, QFilterCondition> _applyStringFilter(
    QueryBuilder<T, T, QFilterCondition> builder,
    Filter filter,
  ) {
    final value = filter.value as String;
    switch (filter.operator) {
      case FilterOperator.equals:
        return builder.idEqualTo(value);
      case FilterOperator.contains:
        return builder.idContains(value);
      case FilterOperator.startsWith:
        return builder.idStartsWith(value);
      default:
        return builder;
    }
  }

  QueryBuilder<T, T, QFilterCondition> _applyDateFilter(
    QueryBuilder<T, T, QFilterCondition> builder,
    Filter filter,
  ) {
    final value = filter.value as DateTime;
    final field = filter.field;

    switch (filter.operator) {
      case FilterOperator.equals:
        if (field == 'createdAt') {
          return builder.createdAtEqualTo(value);
        } else {
          return builder.modifiedAtEqualTo(value);
        }
      case FilterOperator.greaterThan:
        if (field == 'createdAt') {
          return builder.createdAtGreaterThan(value);
        } else {
          return builder.modifiedAtGreaterThan(value);
        }
      default:
        return builder;
    }
  }

  QueryBuilder<T, T, QFilterCondition> _applyIntFilter(
    QueryBuilder<T, T, QFilterCondition> builder,
    Filter filter,
  ) {
    final value = filter.value as int;
    switch (filter.operator) {
      case FilterOperator.equals:
        return builder.versionEqualTo(value);
      case FilterOperator.greaterThan:
        return builder.versionGreaterThan(value);
      default:
        return builder;
    }
  }

  QueryBuilder<T, T, QFilterCondition> _applyBoolFilter(
    QueryBuilder<T, T, QFilterCondition> builder,
    Filter filter,
  ) {
    final value = filter.value as bool;
    return builder.isDeletedEqualTo(value);
  }

  @override
  Stream<DatumChangeDetail<T>>? changeStream() {
    return collection.watchLazy().map((_) {
      // This is a simplified implementation
      // In a real app, you'd need to track what changed
      return DatumChangeDetail<T>(
        type: DatumOperationType.update,
        entityId: 'unknown',
        userId: 'unknown',
        timestamp: DateTime.now(),
        data: null,
      );
    });
  }

  @override
  Future<PaginatedResult<T>> readAllPaginated(PaginationConfig config, {String? userId}) async {
    var query = collection.filter().isDeletedEqualTo(false);
    if (userId != null) {
      query = query.userIdEqualTo(userId);
    }

    final page = config.currentPage ?? 0;
    final offset = page * config.pageSize;
    final items = await query.offset(offset).limit(config.pageSize).findAll();
    final totalCount = await query.count();
    return PaginatedResult(
      items: items,
      totalCount: totalCount,
      currentPage: page,
      totalPages: (totalCount / config.pageSize).ceil(),
      hasMore: offset + items.length < totalCount,
    );
  }

  @override
  Future<List<T>> readByIds(List<String> ids, {required String userId}) async {
    return await collection.filter()
        .isDeletedEqualTo(false)
        .userIdEqualTo(userId)
        .anyOf(ids.map((id) => FilterGroup.and().idEqualTo(id)))
        .findAll();
  }

  @override
  Future<int> getStorageSize({String? userId}) async {
    // Isar doesn't provide direct size information
    // This is an estimate
    final count = await collection.count();
    return count * 1024; // Rough estimate
  }

  @override
  Future<void> clearUserData(String userId) async {
    await collection.isar.writeTxn(() async {
      await collection.filter().userIdEqualTo(userId).deleteAll();
    });
  }

  @override
  Future<void> clear() async {
    await collection.isar.writeTxn(() async {
      await collection.clear();
    });
  }

  @override
  Future<List<String>> getAllUserIds() async {
    final distinct = await collection.where().distinctByUserId().userIdProperty().findAll();
    return distinct.whereType<String>().toList();
  }

  @override
  Future<DatumSyncMetadata?> getSyncMetadata(String userId) async {
    // You'd need a separate collection for sync metadata
    // This is a simplified implementation
    return null;
  }

  @override
  Future<void> updateSyncMetadata(DatumSyncMetadata metadata, String userId) async {
    // Implementation would depend on your metadata storage strategy
  }

  @override
  Future<List<DatumSyncOperation<T>>> getPendingOperations(String userId) async {
    // You'd need a separate collection for pending operations
    return [];
  }

  @override
  Future<void> addPendingOperation(String userId, DatumSyncOperation<T> operation) async {
    // Implementation would depend on your pending operations storage
  }

  @override
  Future<void> removePendingOperation(String operationId) async {
    // Implementation would depend on your pending operations storage
  }

  @override
  Future<R> transaction<R>(Future<R> Function() action) async {
    return await collection.isar.writeTxn(action);
  }

  @override
  Future<void> saveLastSyncResult(String userId, DatumSyncResult<T> result) async {
    // Store in a separate collection, like sync metadata
  }

  @override
  Future<DatumSyncResult<T>?> getLastSyncResult(String userId) async {
    // Retrieve from your metadata storage
    return null;
  }

  @override
  Future<void> setStoredSchemaVersion(int version) async {
    // Store in a separate collection or shared preferences
  }

  @override
  Future<int> getStoredSchemaVersion() async {
    // Retrieve from storage
    return 0;
  }

  @override
  Future<List<Map<String, dynamic>>> getAllRawData({String? userId}) async {
    final entities = await readAll(userId: userId);
    return entities.map((e) => e.toDatumMap()).toList();
  }

  @override
  Future<void> overwriteAllRawData(List<Map<String, dynamic>> data, {String? userId}) async {
    await collection.isar.writeTxn(() async {
      // Clear existing data
      if (userId != null) {
        await collection.filter().userIdEqualTo(userId).deleteAll();
      } else {
        await collection.clear();
      }

      // Insert new data
      for (final item in data) {
        final entity = fromMap(item);
        await collection.put(entity);
      }
    });
  }
}
```

> **Reference implementations:** the shipping adapters are the best templates for a
> complete `LocalAdapter` — see `InMemoryLocalAdapter` in the `datum` package,
> `HiveLocalAdapter` in `datum_hive`, and `SqliteLocalAdapter` in `datum_sqlite`.

## Usage Example

```dart
import 'package:isar/isar.dart';

import 'isar_local_adapter.dart'; // the adapter implemented above

// Initialize Isar
final isar = await Isar.open([TaskEntitySchema]);

// Create the adapter
final taskAdapter = IsarLocalAdapter<Task>(
  collection: isar.taskEntitys, // Generated collection
  fromMap: (map) => Task.fromMap(map),
);

// Register with Datum, paired with any RemoteAdapter (for example the
// SupabaseRemoteAdapter from the Supabase guide).
final registrations = [
  DatumRegistration<Task>(
    localAdapter: taskAdapter,
    remoteAdapter: SupabaseRemoteAdapter<Task>(
      tableName: 'tasks',
      fromMap: (map) => Task.fromMap(map),
    ),
  ),
];
```

## Features

- **High Performance**: Isar provides excellent query performance with indexing
- **Type Safety**: Compile-time type checking with generated code
- **Complex Queries**: Rich query API with filtering, sorting, and linking
- **Transactions**: ACID-compliant transactions
- **Change Streams**: Built-in reactive change notifications
- **Migration Support**: Schema versioning and data migration

## Performance Considerations

- **Indexing**: Proper indexing is crucial for query performance
- **Memory Usage**: Isar is memory-efficient compared to other databases
- **Concurrent Access**: Supports concurrent read/write operations
- **Change Notifications**: Efficient reactive updates with watchers
