---




title: Firebase Remote Adapter
---

This guide shows how to implement a complete Firebase remote adapter for Datum.

## Overview

Firebase provides real-time database capabilities and works well with Datum's synchronization features. This adapter uses Firestore as the backend.

## Setup

Add Firebase dependencies to your `pubspec.yaml`:

```yaml
dependencies:
  cloud_firestore: ^4.0.0
  firebase_core: ^2.0.0
```

## Implementation

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:datum/datum.dart';

class FirebaseRemoteAdapter<T extends DatumEntityInterface> extends RemoteAdapter<T> {
  final String collectionName;
  final T Function(Map<String, dynamic>) fromMap;
  final FirebaseFirestore firestore;

  FirebaseRemoteAdapter({
    required this.collectionName,
    required this.fromMap,
    FirebaseFirestore? firestore,
  }) : firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _collection =>
      firestore.collection(collectionName);

  @override
  Future<void> initialize() async {
    // Firebase is initialized globally
  }

  @override
  Future<void> dispose() async {
    // Firebase is disposed globally
  }

  @override
  Future<AdapterHealthStatus> checkHealth() async {
    try {
      // Try to get a document to check connectivity
      await _collection.limit(1).get();
      return AdapterHealthStatus.healthy;
    } catch (e) {
      return AdapterHealthStatus.unhealthy;
    }
  }

  @override
  Future<bool> isConnected() async {
    // Firebase handles connectivity internally
    return true;
  }

  @override
  Future<T?> read(String id, {String? userId}) async {
    try {
      final doc = await _collection.doc(id).get();
      if (!doc.exists) return null;

      final data = doc.data();
      if (data == null) return null;

      // Check user access if userId is provided
      if (userId != null && data['userId'] != userId) {
        return null;
      }

      return fromMap(data);
    } catch (e) {
      throw Exception('Failed to read from Firestore: $e');
    }
  }

  @override
  Future<List<T>> readAll({String? userId, DatumSyncScope? scope}) async {
    try {
      Query<Map<String, dynamic>> query = _collection;

      // Add user filter if provided
      if (userId != null) {
        query = query.where('userId', isEqualTo: userId);
      }

      // Add scope filters if provided
      if (scope != null) {
        for (final filter in scope.query.filters) {
          if (filter is Filter) {
            query = _applyFilter(query, filter);
          }
        }
      }

      // Filter out soft-deleted documents
      query = query.where('isDeleted', isEqualTo: false);

      final snapshot = await query.get();
      return snapshot.docs.map((doc) => fromMap(doc.data())).toList();
    } catch (e) {
      throw Exception('Failed to read from Firestore: $e');
    }
  }

  Query<Map<String, dynamic>> _applyFilter(
    Query<Map<String, dynamic>> query,
    Filter filter,
  ) {
    switch (filter.operator) {
      case FilterOperator.equals:
        return query.where(filter.field, isEqualTo: filter.value);
      case FilterOperator.greaterThan:
        return query.where(filter.field, isGreaterThan: filter.value);
      case FilterOperator.lessThan:
        return query.where(filter.field, isLessThan: filter.value);
      case FilterOperator.greaterThanOrEqual:
        return query.where(filter.field, isGreaterThanOrEqual: filter.value);
      case FilterOperator.lessThanOrEqual:
        return query.where(filter.field, isLessThanOrEqual: filter.value);
      case FilterOperator.isIn:
        return query.where(filter.field, whereIn: filter.value as List);
      case FilterOperator.isNotIn:
        return query.where(filter.field, whereNotIn: filter.value as List);
      case FilterOperator.arrayContains:
        return query.where(filter.field, arrayContains: filter.value);
      default:
        // Firestore doesn't support all operators natively
        return query;
    }
  }

  @override
  Future<void> create(T entity) async {
    try {
      await _collection.doc(entity.id).set(entity.toDatumMap());
    } catch (e) {
      throw Exception('Failed to create in Firestore: $e');
    }
  }

  @override
  Future<void> update(T entity) async {
    try {
      await _collection.doc(entity.id).update(entity.toDatumMap());
    } catch (e) {
      throw Exception('Failed to update in Firestore: $e');
    }
  }

  @override
  Future<bool> delete(String id, {String? userId}) async {
    try {
      // Soft delete by updating the document
      await _collection.doc(id).update({'isDeleted': true});
      return true;
    } catch (e) {
      throw Exception('Failed to delete in Firestore: $e');
    }
  }

  @override
  Future<T> patch({
    required String id,
    required Map<String, dynamic> delta,
    String? userId,
  }) async {
    try {
      await _collection.doc(id).update(delta);

      // Return the updated document
      final updated = await read(id, userId: userId);
      if (updated == null) {
        throw Exception('Document not found after patch');
      }
      return updated;
    } catch (e) {
      throw Exception('Failed to patch in Firestore: $e');
    }
  }

  @override
  Future<List<T>> query(DatumQuery query, {String? userId}) async {
    try {
      Query<Map<String, dynamic>> firestoreQuery = _collection;

      // Add user filter
      if (userId != null) {
        firestoreQuery = firestoreQuery.where('userId', isEqualTo: userId);
      }

      // Filter out soft-deleted documents
      firestoreQuery = firestoreQuery.where('isDeleted', isEqualTo: false);

      // Apply filters
      for (final filter in query.filters) {
        if (filter is Filter) {
          firestoreQuery = _applyFilter(firestoreQuery, filter);
        }
      }

      // Apply sorting
      for (final sort in query.sorting) {
        firestoreQuery = firestoreQuery.orderBy(
          sort.field,
          descending: sort.descending,
        );
      }

      // Apply pagination
      if (query.offset > 0) {
        // Firestore doesn't support offset directly with where clauses
        // This is a simplified implementation
        firestoreQuery = firestoreQuery.limit(query.offset + (query.limit ?? 100));
      }
      if (query.limit != null) {
        firestoreQuery = firestoreQuery.limit(query.limit!);
      }

      final snapshot = await firestoreQuery.get();
      return snapshot.docs.map((doc) => fromMap(doc.data())).toList();
    } catch (e) {
      throw Exception('Failed to query Firestore: $e');
    }
  }

  @override
  Future<DatumSyncMetadata?> getSyncMetadata(String userId) async {
    try {
      final doc = await firestore.collection('sync_metadata').doc(userId).get();
      if (!doc.exists) return null;

      final data = doc.data();
      if (data == null) return null;

      return DatumSyncMetadata.fromMap(data);
    } catch (e) {
      throw Exception('Failed to get sync metadata from Firestore: $e');
    }
  }

  @override
  Future<void> updateSyncMetadata(DatumSyncMetadata metadata, String userId) async {
    try {
      await firestore.collection('sync_metadata').doc(userId).set(metadata.toMap());
    } catch (e) {
      throw Exception('Failed to update sync metadata in Firestore: $e');
    }
  }

  @override
  Stream<DatumChangeDetail<T>>? get changeStream {
    return _collection.snapshots().map((snapshot) {
      // This is a simplified implementation
      // In a real app, you'd need to analyze the changes
      for (final change in snapshot.docChanges) {
        final type = switch (change.type) {
          DocumentChangeType.added => DatumOperationType.create,
          DocumentChangeType.modified => DatumOperationType.update,
          DocumentChangeType.removed => DatumOperationType.delete,
        };

        final data = change.doc.data();
        if (data != null) {
          final entity = fromMap(data);
          return DatumChangeDetail<T>(
            type: type,
            entityId: entity.id,
            userId: entity.userId,
            timestamp: entity.modifiedAt,
            data: entity,
          );
        }
      }
      return null;
    }).where((detail) => detail != null).cast<DatumChangeDetail<T>>();
  }
}
```

## Usage Example

```dart
import 'firebase_remote_adapter.dart'; // the adapter implemented above

// Create the adapter
final taskAdapter = FirebaseRemoteAdapter<Task>(
  collectionName: 'tasks',
  fromMap: (map) => Task.fromMap(map),
);

// Register with Datum
final registrations = [
  DatumRegistration<Task>(
    localAdapter: HiveLocalAdapter<Task>(
      entityBoxName: 'tasks',
      fromMap: (map) => Task.fromMap(map),
    ),
    remoteAdapter: taskAdapter,
  ),
];
```

## Firestore Security Rules

Set up proper security rules for your Firestore database:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Tasks collection - users can only access their own data
    match /tasks/{taskId} {
      allow read, write: if request.auth != null &&
        resource.data.userId == request.auth.uid;
      allow create: if request.auth != null &&
        request.auth.uid == request.resource.data.userId;
    }

    // Sync metadata - users can only access their own metadata
    match /sync_metadata/{userId} {
      allow read, write: if request.auth != null &&
        request.auth.uid == userId;
    }
  }
}
```

## Features

- **Real-time Synchronization**: Firestore's real-time capabilities enable live data sync
- **Offline Support**: Built-in offline persistence with automatic sync
- **Security Rules**: Granular access control with Firestore security rules
- **Query Support**: Rich querying with Firestore's query capabilities
- **Change Streams**: Real-time change notifications
- **Scalability**: Automatic scaling with Firebase infrastructure

## Performance Considerations

- **Query Limitations**: Firestore has specific query limitations (no OR queries, inequality limitations)
- **Indexing**: Automatic indexing but can be expensive for complex queries
- **Real-time Updates**: Change streams can consume battery and data
- **Batch Operations**: Consider batch writes for multiple operations
- **Pagination**: Implement cursor-based pagination for large datasets
