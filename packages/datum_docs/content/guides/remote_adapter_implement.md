---
title: Remote Adapter Implementation
---



## Example of Remote Adapter


```dart
import 'dart:async';

import 'package:datum/datum.dart';

class TaskRemoteAdapter extends RemoteAdapter<Task> {
  final _changeController =
      StreamController<DatumChangeDetail<Task>>.broadcast();

  @override
  Stream<DatumChangeDetail<Task>>? get changeStream =>
      _changeController.stream;

  @override
  Future<void> initialize() async {
    // Authenticate and set up listeners here.
  }

  @override
  Future<void> create(Task entity) async {
    // POST the entity to your backend.
  }

  @override
  Future<void> update(Task entity) async {
    // PUT the full entity to your backend.
  }

  @override
  Future<bool> delete(String id, {String? userId}) async {
    // DELETE on your backend; return false when nothing was deleted.
    return true;
  }

  @override
  Future<Task?> read(String id, {String? userId}) async {
    // GET a single entity; return null when it doesn't exist.
    return null;
  }

  @override
  Future<List<Task>> readAll({String? userId, DatumSyncScope? scope}) async {
    // GET all entities for the user, optionally narrowed by [scope].
    return [];
  }

  @override
  Future<List<Task>> query(DatumQuery query, {String? userId}) async {
    // Translate the DatumQuery into your backend's query language.
    return [];
  }

  @override
  Future<Task> patch({
    required String id,
    required Map<String, dynamic> delta,
    String? userId,
  }) async {
    // PATCH the delta and return the updated entity.
    throw UnimplementedError();
  }

  @override
  Future<DatumSyncMetadata?> getSyncMetadata(String userId) async => null;

  @override
  Future<void> updateSyncMetadata(
      DatumSyncMetadata metadata, String userId) async {}

  @override
  Future<bool> isConnected() async => true;

  @override
  Future<void> dispose() async {
    await _changeController.close();
  }
}
```

> **Reference implementation:** `HttpRemoteAdapter` in the `datum_test` package is
> a complete REST `RemoteAdapter` (with `DeltaSyncCapable` incremental pulls and
> proper exception mapping) that you can copy as a starting point.

## Complete Supabase Adapter Example

Here's a complete implementation of a `RemoteAdapter` for Supabase, showing how to integrate with a real backend service:

```dart
import 'dart:async';

import 'package:datum/datum.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:recase/recase.dart';

class SupabaseRemoteAdapter<T extends DatumEntityInterface>
    extends RemoteAdapter<T> {
  final String tableName;
  final T Function(Map<String, dynamic>) fromMap;
  final SupabaseClient? _clientOverride;

  SupabaseRemoteAdapter({
    required this.tableName,
    required this.fromMap,
    // This is for testing purposes only.
    SupabaseClient? clientOverride,
  }) : _clientOverride = clientOverride;

  RealtimeChannel? _channel;
  StreamController<DatumChangeDetail<T>>? _streamController;

  // Store related entity channels for cleanup
  final Map<String, RealtimeChannel> _relatedChannels = {};

  SupabaseClient get _client => _clientOverride ?? Supabase.instance.client;
  String get _metadataTableName => 'sync_metadata';

  @override
  Future<bool> delete(String id, {String? userId}) async {
    await _client.from(tableName).delete().eq('id', id);
    return true;
  }

  @override
  Future<AdapterHealthStatus> checkHealth() async {
    final auth = Supabase.instance.client.auth.currentSession?.accessToken == null;
    return auth == true ? AdapterHealthStatus.unhealthy : AdapterHealthStatus.healthy;
  }

  @override
  Future<List<T>> readAll({String? userId, DatumSyncScope? scope}) async {
    PostgrestFilterBuilder queryBuilder = _client.from(tableName).select();

    // Apply filters from the sync scope, if provided.
    if (scope != null) {
      for (final condition in scope.query.filters) {
        queryBuilder = _applyFilter(queryBuilder, condition);
      }
    }

    final response = await queryBuilder;
    if (response is List<Map<String, dynamic>>) {
      return response.map<T>((json) => fromMap(_toCamelCase(json))).toList();
    } else {
      return [];
    }
  }

  @override
  Future<T?> read(String id, {String? userId}) async {
    final response = await _client.from(tableName).select().eq('id', id);

    if (response.length > 1) {
      return null;
    }
    return fromMap(_toCamelCase(response.first));
  }

  @override
  Future<DatumSyncMetadata?> getSyncMetadata(String userId) async {
    final response = await _client
        .from(_metadataTableName)
        .select()
        .eq('user_id', userId)
        .maybeSingle();

    if (response == null) {
      return null;
    }
    return DatumSyncMetadata.fromMap(_toCamelCase(response));
  }

  @override
  Future<bool> isConnected() async => true;

  @override
  Future<void> create(T entity) async {
    final data = _toSnakeCase(entity.toDatumMap(target: MapTarget.remote));
    // Ensure userId is in the payload
    data['user_id'] = entity.userId;
    final response = await _client
        .from(tableName)
        .upsert(data, onConflict: 'id')
        .select()
        .maybeSingle();
    if (response == null) {
      throw Exception('Failed to push item: upsert did not return the expected record.');
    }
  }

  @override
  Future<T> patch({
    required String id,
    required Map<String, dynamic> delta,
    String? userId,
  }) async {
    final snakeCaseDelta = _toSnakeCase(delta);
    final response = await _client
        .from(tableName)
        .update(snakeCaseDelta)
        .eq('id', id)
        .select()
        .maybeSingle();
    if (response == null) {
      throw Exception('Failed to patch item: record not found.');
    }
    return fromMap(_toCamelCase(response));
  }

  @override
  Future<void> updateSyncMetadata(
      DatumSyncMetadata metadata, String userId) async {
    final data = _toSnakeCase(metadata.toMap());
    data['user_id'] = userId;

    await _client.from(_metadataTableName).upsert(data);
  }

  @override
  Stream<DatumChangeDetail<T>>? get changeStream {
    _streamController ??= StreamController<DatumChangeDetail<T>>.broadcast(
      onListen: _subscribeToChanges,
      onCancel: unsubscribeFromChanges,
    );
    return _streamController?.stream;
  }

  void _subscribeToChanges() {
    _channel = _client
        .channel('public:$tableName')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: tableName,
          callback: (payload) {
            DatumOperationType? type;
            Map<String, dynamic>? record;

            switch (payload.eventType) {
              case PostgresChangeEvent.insert:
                type = DatumOperationType.create;
                record = payload.newRecord;
                break;
              case PostgresChangeEvent.update:
                type = DatumOperationType.update;
                record = payload.newRecord;
                break;
              case PostgresChangeEvent.delete:
                type = DatumOperationType.delete;
                record = payload.oldRecord;
                break;
              case PostgresChangeEvent.all:
                break;
            }

            if (type != null && record != null) {
              final item = fromMap(_toCamelCase(record));
              final userId = item.userId.isNotEmpty
                  ? item.userId
                  : _client.auth.currentUser?.id;
              if (userId == null) return;

              _streamController?.add(
                DatumChangeDetail<T>(
                  type: type,
                  entityId: item.id,
                  userId: userId,
                  timestamp: item.modifiedAt,
                  data: item,
                ),
              );
            }
          },
        )..subscribe();
  }

  @override
  Future<void> unsubscribeFromChanges() async {
    if (_channel != null) {
      await _client.removeChannel(_channel!);
      _channel = null;
    }

    // Unsubscribe from all related entity channels
    for (final channel in _relatedChannels.values) {
      await _client.removeChannel(channel);
    }
    _relatedChannels.clear();
  }

  @override
  Future<void> resubscribeToChanges() async {
    unsubscribeFromChanges();
    _subscribeToChanges();
  }

  @override
  Future<void> dispose() async {
    await unsubscribeFromChanges();
    await _streamController?.close();
    return super.dispose();
  }

  @override
  Future<void> initialize() async {
    if (_channel == null) {
      await unsubscribeFromChanges();
      _subscribeToChanges();
    }
    return Future.value();
  }

  @override
  Future<List<T>> query(DatumQuery query, {String? userId}) async {
    PostgrestFilterBuilder queryBuilder = _client.from(tableName).select();

    for (final condition in query.filters) {
      queryBuilder = _applyFilter(queryBuilder, condition);
    }

    final response = await queryBuilder;
    return response.map<T>((json) => fromMap(_toCamelCase(json))).toList();
  }

  @override
  Future<void> update(T entity) async {
    final data = _toSnakeCase(entity.toDatumMap(target: MapTarget.remote));
    data['user_id'] = entity.userId;
    await _client.from(tableName).upsert(data, onConflict: 'id');
  }

  PostgrestFilterBuilder _applyFilter(
    PostgrestFilterBuilder builder,
    FilterCondition condition,
  ) {
    if (condition is Filter) {
      final field = condition.field.snakeCase;
      final value = condition.value;

      switch (condition.operator) {
        case FilterOperator.equals:
          return builder.eq(field, value);
        case FilterOperator.notEquals:
          return builder.neq(field, value);
        case FilterOperator.lessThan:
          return builder.lt(field, value);
        case FilterOperator.lessThanOrEqual:
          return builder.lte(field, value);
        case FilterOperator.greaterThan:
          return builder.gt(field, value);
        case FilterOperator.greaterThanOrEqual:
          return builder.gte(field, value);
        case FilterOperator.arrayContains:
          return builder.contains(field, value);
        case FilterOperator.isIn:
          return builder.inFilter(field, value as List);
        default:
          throw UnsupportedError('Unsupported query operator: ${condition.operator}');
      }
    }
    return builder;
  }
}

Map<String, dynamic> _toSnakeCase(Map<String, dynamic> map) {
  final newMap = <String, dynamic>{};
  map.forEach((key, value) {
    newMap[key.snakeCase] = value;
  });
  return newMap;
}

Map<String, dynamic> _toCamelCase(Map<String, dynamic> map) {
  final newMap = <String, dynamic>{};
  map.forEach((key, value) {
    newMap[key.camelCase] = value;
  });
  return newMap;
}
```

### Using the Supabase Adapter

```dart
import 'supabase_remote_adapter.dart'; // the adapter implemented above

// Create the adapter
final taskRemoteAdapter = SupabaseRemoteAdapter<Task>(
  tableName: 'tasks',
  fromMap: Task.fromMap,
);

// Register with Datum
final registrations = [
  DatumRegistration<Task>(
    localAdapter: localAdapter,
    remoteAdapter: taskRemoteAdapter,
  ),
];

// Initialize Datum
final result = await Datum.initialize(
  config: config,
  connectivityChecker: connectivityChecker,
  registrations: registrations,
);
```

### Supabase Database Setup

For the Supabase adapter to work, you need to set up your database tables with the correct structure and permissions:

```sql
-- Enable Row Level Security
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE sync_metadata ENABLE ROW LEVEL SECURITY;

-- Create policies for users table
CREATE POLICY "Users can view their own data" ON users
  FOR SELECT USING (auth.uid()::text = user_id);

CREATE POLICY "Users can insert their own data" ON users
  FOR INSERT WITH CHECK (auth.uid()::text = user_id);

CREATE POLICY "Users can update their own data" ON users
  FOR UPDATE USING (auth.uid()::text = user_id);

-- Create policies for sync_metadata table
CREATE POLICY "Users can manage their own sync metadata" ON sync_metadata
  FOR ALL USING (auth.uid()::text = user_id);
```

### Advanced Features

The example Supabase adapter includes several advanced features for production use:

#### Authentication Monitoring

```dart no-verify
// Monitor authentication state changes (excerpt of the Supabase adapter above)
void startAuthMonitoring() {
  _authSubscription = _client.auth.onAuthStateChange.listen((authState) {
    final isAuthenticated = authState.session != null;
    _updateAuthenticationState(isAuthenticated);

    if (!isAuthenticated) {
      // Stop syncing when user logs out
      unsubscribeFromChanges();
    } else {
      // Resume syncing when user logs in
      if (_channel == null) {
        _subscribeToChanges();
      }
    }
  });
}
```

#### Retry Logic for Subscriptions

```dart no-verify
class _SubscriptionRetryManager {
  static const int maxRetries = 5;
  static const Duration baseRetryDelay = Duration(seconds: 1);

  void scheduleRetry(String tableName, bool isAuthenticated, VoidCallback retryCallback) {
    if (_isRetrying || !isAuthenticated) return;

    _trackFailure();
    if (_retryCount >= maxRetries) return;

    _isRetrying = true;
    _retryCount++;

    final delay = _calculateDelay();
    Timer(delay, () {
      if (!isAuthenticated) return;
      _isRetrying = false;
      retryCallback();
    });
  }

  Duration _calculateDelay() {
    var delaySeconds = (baseRetryDelay.inSeconds * (1 << (_retryCount - 1))).clamp(1, 30);
    if (_consecutiveFailures >= 3) {
      delaySeconds = (delaySeconds * 5).clamp(30, 300);
    }
    return Duration(seconds: delaySeconds);
  }
}
```

#### Relationship Fetching

```dart no-verify
Future<List<R>> fetchRelated<R extends DatumEntityInterface>(
  RelationalDatumEntity parent,
  String relationName,
  RemoteAdapter<R> relatedAdapter,
) async {
  final relatedSupabaseAdapter = relatedAdapter as SupabaseRemoteAdapter<R>;
  final relatedTableName = relatedSupabaseAdapter.tableName;

  PostgrestFilterBuilder queryBuilder = _client.from(relatedTableName).select();

  final relation = parent.relations[relationName];

  switch (relation) {
    case BelongsTo(:final foreignKey, :final localKey):
      final relatedKeyValue = parent.toDatumMap()[localKey];
      if (relatedKeyValue == null) return [];
      queryBuilder = queryBuilder.eq(foreignKey.snakeCase, relatedKeyValue);
      break;
    case HasMany(:final foreignKey, :final localKey):
    case HasOne(:final foreignKey, :final localKey):
      final foreignKeyColumn = foreignKey.snakeCase;
      final localKeyValue = parent.toDatumMap()[localKey];
      if (localKeyValue == null) return [];
      queryBuilder = queryBuilder.eq(foreignKeyColumn, localKeyValue);
      break;
    case ManyToMany(:final otherForeignKey, :final otherLocalKey, :final thisForeignKey, :final thisLocalKey):
      // Handle many-to-many relationships with junction tables
      final pivotAdapter = Datum.manager().remoteAdapter;
      if (pivotAdapter is! SupabaseRemoteAdapter) {
        throw ArgumentError('Pivot adapter must be a SupabaseRemoteAdapter');
      }
      final pivotTableName = pivotAdapter.tableName;

      final parentIdValue = parent.toDatumMap()[thisLocalKey];
      if (parentIdValue == null) return [];

      final junctionRecords = await _client
          .from(pivotTableName)
          .select(otherForeignKey.snakeCase)
          .eq(thisForeignKey.snakeCase, parentIdValue);

      if (junctionRecords.isEmpty) return [];

      final relatedIds = junctionRecords
          .map((record) => record[otherForeignKey.snakeCase])
          .whereType<String>()
          .toList();

      if (relatedIds.isEmpty) return [];
      queryBuilder = queryBuilder.inFilter(otherLocalKey.snakeCase, relatedIds);
      break;
  }

  final response = await queryBuilder;
  return response.map<R>((json) => relatedSupabaseAdapter.fromMap(_toCamelCase(json))).toList();
}
```

#### Real-time Relationship Watching

```dart no-verify
Stream<List<R>> watchRelated<R extends DatumEntityInterface>(
  RelationalDatumEntity parent,
  String relationName,
  RemoteAdapter<R> relatedAdapter,
) {
  final relatedSupabaseAdapter = relatedAdapter as SupabaseRemoteAdapter<R>;
  final relatedTableName = relatedSupabaseAdapter.tableName;
  final relation = parent.relations[relationName];

  late StreamController<List<R>> controller;
  RealtimeChannel? channel;

  Future<void> fetchAndEmit() async {
    try {
      final items = await fetchRelated<R>(parent, relationName, relatedAdapter);
      if (!controller.isClosed) {
        controller.add(items);
      }
    } catch (e) {
      if (!controller.isClosed) {
        controller.addError(e);
      }
    }
  }

  void setupRealtimeSubscription() {
    final channelName = 'related:$relatedTableName:${parent.id}:$relationName';

    channel = _client.channel(channelName).onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: relatedTableName,
      callback: (payload) => fetchAndEmit(),
    );

    // For ManyToMany relationships, also watch the pivot table
    if (relation is ManyToMany) {
      final pivotAdapter = Datum.manager().remoteAdapter;
      if (pivotAdapter is SupabaseRemoteAdapter) {
        final pivotTableName = pivotAdapter.tableName;
        final pivotChannelName = 'pivot:$pivotTableName:${parent.id}:$relationName';

        final pivotChannel = _client
            .channel(pivotChannelName)
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: pivotTableName,
              callback: (payload) => fetchAndEmit(),
            );

        pivotChannel.subscribe();
        _relatedChannels[pivotChannelName] = pivotChannel;
      }
    }

    channel?.subscribe();
    if (channel != null) {
      _relatedChannels[channelName] = channel!;
    }
  }

  controller = StreamController<List<R>>.broadcast(
    onListen: () {
      fetchAndEmit();
      setupRealtimeSubscription();
    },
    onCancel: () async {
      if (channel != null) {
        await _client.removeChannel(channel!);
        _relatedChannels.remove('related:$relatedTableName:${parent.id}:$relationName');
      }
      // Clean up pivot channel if it exists
    },
  );

  return controller.stream;
}
```

### Error Handling

The adapter includes comprehensive error handling for common Supabase issues:

- **Authentication errors**: Returns `AdapterHealthStatus.unhealthy` when not authenticated
- **Network errors**: Throws appropriate exceptions for connection issues
- **Permission errors**: Handles RLS policy violations with graceful degradation
- **Data validation**: Validates responses from Supabase
- **Subscription failures**: Implements retry logic with exponential backoff

### Production Considerations

#### Connection Management

```dart no-verify
// Proper cleanup in dispose (excerpt of the Supabase adapter above)
@override
Future<void> dispose() async {
  _retryManager.dispose();
  await unsubscribeFromChanges();
  await _streamController?.close();
  await _stopAuthMonitoring();
  await _authStateController.close();
  return super.dispose();
}
```

#### Health Monitoring

```dart no-verify
@override
Future<AdapterHealthStatus> checkHealth() async {
  final hasSession = Supabase.instance.client.auth.currentSession?.accessToken != null;
  return hasSession ? AdapterHealthStatus.healthy : AdapterHealthStatus.unhealthy;
}
```

This complete Supabase adapter example demonstrates how to implement a production-ready remote adapter for Datum with real-time synchronization, authentication monitoring, retry logic, relationship support, and comprehensive error handling.
