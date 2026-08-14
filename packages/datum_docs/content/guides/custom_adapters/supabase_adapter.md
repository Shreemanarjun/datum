---
title: Supabase Remote Adapter
---

This guide shows how to implement a complete Supabase remote adapter for Datum.

## Overview

Supabase provides real-time database capabilities with PostgreSQL and works seamlessly with Datum's synchronization features. This adapter uses Supabase's realtime subscriptions for live data sync and PostgREST for CRUD operations.

## Setup

Add Supabase dependencies to your `pubspec.yaml`:

```yaml
dependencies:
  supabase_flutter: ^2.0.0
  recase: ^4.1.0
```

Initialize Supabase in your app:

```dart
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  await Supabase.initialize(
    url: 'YOUR_SUPABASE_URL',
    anonKey: 'YOUR_SUPABASE_ANON_KEY',
  );
  runApp(MyApp());
}
```

## Implementation

```dart
import 'dart:async';
import 'dart:ui';

import 'package:datum/datum.dart';
import 'package:example/bootstrap.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:recase/recase.dart';

/// Manages retry logic for Supabase realtime subscriptions
class _SubscriptionRetryManager {
  Timer? _retryTimer;
  int _retryCount = 0;
  bool _isRetrying = false;
  DateTime? _lastRetryTime;
  int _consecutiveFailures = 0;

  static const int maxRetries = 5;
  static const Duration baseRetryDelay = Duration(seconds: 1);

  bool get isRetrying => _isRetrying;
  bool get hasFailures => _retryCount > 0 || _consecutiveFailures > 0;

  void scheduleRetry(
      String tableName, bool isAuthenticated, VoidCallback retryCallback) {
    if (_isRetrying || !isAuthenticated) {
      talker.debug(
          "Skipping retry: already retrying or not authenticated for table: $tableName");
      return;
    }

    _trackFailure();

    if (_retryCount >= maxRetries) {
      talker.error(
          "Max retry attempts reached for table: $tableName. Giving up.");
      return;
    }

    _isRetrying = true;
    _retryCount++;

    final delay = _calculateDelay();
    talker.warning(
        "Scheduling retry attempt $_retryCount for table: $tableName in ${delay.inSeconds} seconds");

    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      if (!isAuthenticated) {
        talker.debug(
            "Skipping retry: user not authenticated for table: $tableName");
        _isRetrying = false;
        return;
      }

      talker.info(
          "Retrying subscription for table: $tableName (attempt $_retryCount)");
      _isRetrying = false;
      retryCallback();
    });
  }

  void _trackFailure() {
    final now = DateTime.now();
    if (_lastRetryTime != null &&
        now.difference(_lastRetryTime!).inSeconds < 30) {
      _consecutiveFailures++;
    } else {
      _consecutiveFailures = 1;
    }
    _lastRetryTime = now;
  }

  Duration _calculateDelay() {
    var delaySeconds =
        (baseRetryDelay.inSeconds * (1 << (_retryCount - 1))).clamp(1, 30);
    if (_consecutiveFailures >= 3) {
      delaySeconds = (delaySeconds * 5).clamp(30, 300);
    }
    return Duration(seconds: delaySeconds);
  }

  void reset() {
    _retryCount = 0;
    _isRetrying = false;
    _retryTimer?.cancel();
    _retryTimer = null;
    _consecutiveFailures = 0;
    _lastRetryTime = null;
  }

  void dispose() {
    _retryTimer?.cancel();
  }
}

class SupabaseRemoteAdapter<T extends DatumEntityInterface>
    extends RemoteAdapter<T> {
  final String tableName;
  final T Function(Map<String, dynamic>) fromMap;
  final SupabaseClient? _clientOverride;

  SupabaseRemoteAdapter({
    required this.tableName,
    required this.fromMap,
    SupabaseClient? clientOverride,
  }) : _clientOverride = clientOverride;

  // Core components
  RealtimeChannel? _channel;
  StreamController<DatumChangeDetail<T>>? _streamController;
  final Map<String, RealtimeChannel> _relatedChannels = {};
  final _SubscriptionRetryManager _retryManager = _SubscriptionRetryManager();

  // Authentication
  StreamSubscription<AuthState>? _authSubscription;
  bool _isAuthenticated = false;
  final StreamController<bool> _authStateController =
      StreamController<bool>.broadcast();

  SupabaseClient get _client => _clientOverride ?? Supabase.instance.client;
  String get _metadataTableName => 'sync_metadata';

  Stream<bool> get authStateStream => _authStateController.stream;

  @override
  Future<bool> delete(String id, {String? userId}) async {
    try {
      await _client.from(tableName).delete().eq(
            'id',
            id,
          );
      return true;
    } on PostgrestException catch (e) {
      // PGRST116: "Cannot coerce the result to a single JSON object" - means no rows were affected
      if (e.code == 'PGRST116') {
        throw EntityNotFoundException(
          message: 'Entity with id $id not found in table $tableName',
        );
      }
      rethrow;
    }
  }

  @override
  Future<AdapterHealthStatus> checkHealth() async {
    final auth =
        Supabase.instance.client.auth.currentSession?.accessToken == null;
    return auth == true
        ? AdapterHealthStatus.unhealthy
        : AdapterHealthStatus.healthy;
  }

  @override
  Future<List<T>> readAll({String? userId, DatumSyncScope? scope}) async {
    talker.info(
        "🔍 [Adapter] readAll called for table: $tableName, userId: $userId");
    talker.debug("🔍 [Adapter] scope: $scope");

    try {
      PostgrestFilterBuilder queryBuilder = _client.from(tableName).select();
      talker.debug("🔍 [Adapter] Created query builder for table: $tableName");

      // Apply filters from the sync scope, if provided.
      if (scope != null) {
        talker.debug(
            "🔍 [Adapter] Applying ${scope.query.filters.length} filters");
        for (final condition in scope.query.filters) {
          queryBuilder = _applyFilter(queryBuilder, condition);
          talker.debug("🔍 [Adapter] Applied filter: $condition");
        }
      }

      talker.debug("🔍 [Adapter] Executing query for table: $tableName");
      final response = await queryBuilder;
      talker.info(
          "✅ [Adapter] Query successful for table: $tableName, response type: ${response.runtimeType}");

      if (response is List<Map<String, dynamic>>) {
        final items =
            response.map<T>((json) => fromMap(_toCamelCase(json))).toList();
        talker.info(
            "✅ [Adapter] Successfully parsed ${items.length} items from table: $tableName");
        return items;
      } else {
        talker.warning(
            "⚠️ [Adapter] Unexpected response type for table: $tableName - expected List<Map<String, dynamic>>, got ${response.runtimeType}");
        return [];
      }
    } catch (e, stackTrace) {
      talker.error(
          "❌ [Adapter] readAll failed for table: $tableName - $e", stackTrace);
      rethrow;
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
    talker.info(
        "🔍 [Adapter] getSyncMetadata called for userId: $userId, table: $_metadataTableName");

    try {
      talker.debug(
          "🔍 [Adapter] Executing query: SELECT from $_metadataTableName WHERE user_id = $userId");
      final response = await _client
          .from(_metadataTableName)
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      talker.info(
          "✅ [Adapter] getSyncMetadata query successful, response: ${response != null ? 'found' : 'null'}");

      if (response == null) {
        talker.debug(
            "🔍 [Adapter] No sync metadata found for user $userId, returning null");
        return null;
      }

      talker.debug("🔍 [Adapter] Parsing sync metadata response: $response");
      final metadata = DatumSyncMetadata.fromMap(response);
      talker.info(
          "✅ [Adapter] Successfully parsed sync metadata for user $userId");
      return metadata;
    } catch (e, stackTrace) {
      talker.error("❌ [Adapter] getSyncMetadata failed for user $userId - $e",
          stackTrace);
      rethrow;
    }
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
      throw Exception(
        'Failed to push item: upsert did not return the expected record. Check RLS policies.',
      );
    }
  }

  @override
  Future<T> patch({
    required String id,
    required Map<String, dynamic> delta,
    String? userId,
  }) async {
    try {
      final snakeCaseDelta = _toSnakeCase(delta);
      final response = await _client
          .from(tableName)
          .update(snakeCaseDelta)
          .eq('id', id)
          .select()
          .maybeSingle();
      if (response == null) {
        throw EntityNotFoundException(
          message:
              'Failed to patch item: record not found or RLS policy prevented selection.',
        );
      }
      return fromMap(_toCamelCase(response));
    } on PostgrestException catch (e) {
      // PGRST116: "Cannot coerce the result to a single JSON object" - means no rows were affected
      if (e.code == 'PGRST116') {
        throw EntityNotFoundException(
          message:
              'Entity with id $id not found in table $tableName during patch operation',
        );
      }
      rethrow;
    }
  }

  @override
  Stream<List<T>>? watchAll({String? userId, DatumSyncScope? scope}) {
    talker.info("👀 [Adapter] watchAll called for table: $tableName, userId: $userId");

    if (!_isAuthenticated) {
      talker.warning("Cannot watch table '$tableName': user not authenticated");
      return null;
    }

    late StreamController<List<T>> controller;
    RealtimeChannel? channel;

    Future<void> fetchAndEmit() async {
      try {
        talker.debug("🔄 [Adapter] Fetching current data for watchAll on table: $tableName");
        final items = await readAll(userId: userId, scope: scope);
        if (!controller.isClosed) {
          controller.add(items);
          talker.debug("✅ [Adapter] Emitted ${items.length} items for watchAll on table: $tableName");
        }
      } catch (e, stackTrace) {
        talker.error("❌ [Adapter] Failed to fetch data for watchAll on table '$tableName': $e", stackTrace);
        if (!controller.isClosed) {
          controller.addError(e);
        }
      }
    }

    void setupRealtimeSubscription() {
      final channelName = 'watchAll:$tableName:${userId ?? 'all'}';

      talker.debug("📡 [Adapter] Setting up realtime subscription for watchAll on table: $tableName");

      channel = _client
          .channel(channelName)
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: tableName,
            callback: (payload) {
              talker.info('📡 [Adapter] Change detected for watchAll on table: $tableName - ${payload.eventType}');

              // For watchAll, we need to re-fetch all data when any change occurs
              // In a production app, you might want to be more selective about when to re-fetch
              fetchAndEmit();
            },
          );

      channel?.subscribe(
        (status, error) {
          talker.debug("📡 [Adapter] watchAll subscription status for table '$tableName': $status");
          if (error != null) {
            talker.error("❌ [Adapter] watchAll subscription error for table '$tableName': $error");
            if (!controller.isClosed) {
              controller.addError(error);
            }
          } else if (status == RealtimeSubscribeStatus.subscribed) {
            talker.info("✅ [Adapter] Successfully subscribed to watchAll for table: $tableName");
          }
        },
      );

      if (channel != null) {
        _relatedChannels[channelName] = channel!;
      }
    }

    controller = StreamController<List<T>>.broadcast(
      onListen: () {
        talker.debug("👂 [Adapter] watchAll stream listened for table: $tableName");
        // Fetch initial data
        fetchAndEmit();
        // Setup realtime subscription
        setupRealtimeSubscription();
      },
      onCancel: () async {
        talker.debug("🚫 [Adapter] watchAll stream cancelled for table: $tableName");
        if (channel != null) {
          await _client.removeChannel(channel!);
          _relatedChannels.remove('watchAll:$tableName:${userId ?? 'all'}');
        }
      },
    );

    return controller.stream;
  }

  @override
  Stream<T?>? watchById(String id, {String? userId}) {
    talker.info("👀 [Adapter] watchById called for table: $tableName, id: $id, userId: $userId");

    if (!_isAuthenticated) {
      talker.warning("Cannot watch table '$tableName': user not authenticated");
      return null;
    }

    late StreamController<T?> controller;
    RealtimeChannel? channel;

    Future<void> fetchAndEmit() async {
      try {
        talker.debug("🔄 [Adapter] Fetching current data for watchById on table: $tableName, id: $id");
        final item = await read(id, userId: userId);
        if (!controller.isClosed) {
          controller.add(item);
          talker.debug("✅ [Adapter] Emitted item for watchById on table: $tableName, id: $id (found: ${item != null})");
        }
      } catch (e, stackTrace) {
        talker.error("❌ [Adapter] Failed to fetch data for watchById on table '$tableName', id '$id': $e", stackTrace);
        if (!controller.isClosed) {
          controller.addError(e);
        }
      }
    }

    void setupRealtimeSubscription() {
      final channelName = 'watchById:$tableName:$id';

      talker.debug("📡 [Adapter] Setting up realtime subscription for watchById on table: $tableName, id: $id");

      channel = _client
          .channel(channelName)
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: tableName,
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id',
              value: id,
            ),
            callback: (payload) {
              talker.info('📡 [Adapter] Change detected for watchById on table: $tableName, id: $id - ${payload.eventType}');

              // For watchById, we emit the updated item or null for deletes
              if (payload.eventType == PostgresChangeEvent.delete) {
                if (!controller.isClosed) {
                  controller.add(null);
                  talker.debug("✅ [Adapter] Emitted null for deleted item in watchById on table: $tableName, id: $id");
                }
              } else {
                // For insert/update, fetch and emit the current item
                fetchAndEmit();
              }
            },
          );

      channel?.subscribe(
        (status, error) {
          talker.debug("📡 [Adapter] watchById subscription status for table '$tableName', id '$id': $status");
          if (error != null) {
            talker.error("❌ [Adapter] watchById subscription error for table '$tableName', id '$id': $error");
            if (!controller.isClosed) {
              controller.addError(error);
            }
          } else if (status == RealtimeSubscribeStatus.subscribed) {
            talker.info("✅ [Adapter] Successfully subscribed to watchById for table: $tableName, id: $id");
          }
        },
      );

      if (channel != null) {
        _relatedChannels[channelName] = channel!;
      }
    }

    controller = StreamController<T?>.broadcast(
      onListen: () {
        talker.debug("👂 [Adapter] watchById stream listened for table: $tableName, id: $id");
        // Fetch initial data
        fetchAndEmit();
        // Setup realtime subscription
        setupRealtimeSubscription();
      },
      onCancel: () async {
        talker.debug("🚫 [Adapter] watchById stream cancelled for table: $tableName, id: $id");
        if (channel != null) {
          await _client.removeChannel(channel!);
          _relatedChannels.remove('watchById:$tableName:$id');
        }
      },
    );

    return controller.stream;
  }

  @override
  Stream<List<T>>? watchQuery(DatumQuery query, {String? userId}) {
    talker.info("👀 [Adapter] watchQuery called for table: $tableName, userId: $userId");

    if (!_isAuthenticated) {
      talker.warning("Cannot watch table '$tableName': user not authenticated");
      return null;
    }

    late StreamController<List<T>> controller;
    RealtimeChannel? channel;

    Future<void> fetchAndEmit() async {
      try {
        talker.debug("🔄 [Adapter] Fetching current data for watchQuery on table: $tableName");
        final items = await this.query(query, userId: userId);
        if (!controller.isClosed) {
          controller.add(items);
          talker.debug("✅ [Adapter] Emitted ${items.length} items for watchQuery on table: $tableName");
        }
      } catch (e, stackTrace) {
        talker.error("❌ [Adapter] Failed to fetch data for watchQuery on table '$tableName': $e", stackTrace);
        if (!controller.isClosed) {
          controller.addError(e);
        }
      }
    }

    void setupRealtimeSubscription() {
      final channelName = 'watchQuery:$tableName:${userId ?? 'all'}';

      talker.debug("📡 [Adapter] Setting up realtime subscription for watchQuery on table: $tableName");

      channel = _client
          .channel(channelName)
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: tableName,
            callback: (payload) {
              talker.info('📡 [Adapter] Change detected for watchQuery on table: $tableName - ${payload.eventType}');

              // For watchQuery, we need to re-evaluate the query when any change occurs
              // In a production app, you might want to be more selective about when to re-fetch
              // based on whether the changed record matches the query filters
              fetchAndEmit();
            },
          );

      channel?.subscribe(
        (status, error) {
          talker.debug("📡 [Adapter] watchQuery subscription status for table '$tableName': $status");
          if (error != null) {
            talker.error("❌ [Adapter] watchQuery subscription error for table '$tableName': $error");
            if (!controller.isClosed) {
              controller.addError(error);
            }
          } else if (status == RealtimeSubscribeStatus.subscribed) {
            talker.info("✅ [Adapter] Successfully subscribed to watchQuery for table: $tableName");
          }
        },
      );

      if (channel != null) {
        _relatedChannels[channelName] = channel!;
      }
    }

    controller = StreamController<List<T>>.broadcast(
      onListen: () {
        talker.debug("👂 [Adapter] watchQuery stream listened for table: $tableName");
        // Fetch initial data
        fetchAndEmit();
        // Setup realtime subscription
        setupRealtimeSubscription();
      },
      onCancel: () async {
        talker.debug("🚫 [Adapter] watchQuery stream cancelled for table: $tableName");
        if (channel != null) {
          await _client.removeChannel(channel!);
          _relatedChannels.remove('watchQuery:$tableName:${userId ?? 'all'}');
        }
      },
    );

    return controller.stream;
  }

  @override
  Future<void> updateSyncMetadata(
      DatumSyncMetadata metadata, String userId) async {
    // Check if user is authenticated before attempting to update sync metadata
    if (!_isAuthenticated) {
      talker.warning(
          "Skipping sync metadata update for user $userId: User is not authenticated");
      return;
    }

    talker
        .debug("Updating sync metadata for user: $userId with data: $metadata");
    final data = _toSnakeCase(metadata.toMap());
    data['user_id'] = userId;

    try {
      await _client.from(_metadataTableName).upsert(data);
    } catch (e) {
      // Handle RLS policy violations gracefully
      if (e is PostgrestException && e.code == '42501') {
        talker.warning(
            "Failed to update sync metadata due to RLS policy violation. User may have logged out.");
        // Mark as unauthenticated to prevent further attempts
        _updateAuthenticationState(false);
      } else {
        // Re-throw other exceptions
        rethrow;
      }
    }
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
    talker.info("Subscribing to Supabase changes for table: $tableName");

    // Check authentication state before subscribing
    final currentUser = _client.auth.currentUser;
    final hasSession = _client.auth.currentSession != null;
    talker.debug(
        "Subscription attempt - Authenticated: $_isAuthenticated, Current user: ${currentUser?.id}, Has session: $hasSession");

    if (!_isAuthenticated) {
      talker.warning(
          "Attempting to subscribe to table '$tableName' while not authenticated. Delaying subscription until authenticated.");
      // Don't attempt subscription if not authenticated - let auth monitoring handle it
      return;
    }

    try {
      talker.debug("Creating realtime channel for table: $tableName");
      _channel = _client
          .channel(
            'public:$tableName',
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: tableName,
            callback: (payload) {
              talker.info(
                  'Received Supabase change: ${payload.eventType} for table: $tableName');
              talker.debug('Payload: $payload');

              DatumOperationType? type;
              Map<String, dynamic>? record;

              switch (payload.eventType) {
                case PostgresChangeEvent.insert:
                  type = DatumOperationType.create;
                  record = payload.newRecord;
                  talker.debug('Insert event detected for table: $tableName');
                  break;
                case PostgresChangeEvent.update:
                  type = DatumOperationType.update;
                  record = payload.newRecord;
                  talker.debug('Update event detected for table: $tableName');
                  break;
                case PostgresChangeEvent.delete:
                  type = DatumOperationType.delete;
                  record = payload.oldRecord;
                  talker.debug('Delete event detected for table: $tableName');
                  break;
                case PostgresChangeEvent.all:
                  talker.debug(
                      'Received "all" event type for table: $tableName, ignoring.');
                  break;
              }

              if (type != null && record != null) {
                talker.debug(
                    'Processing change of type $type for record: $record in table: $tableName');
                final item = fromMap(_toCamelCase(record));
                // When a delete event comes from Supabase, the oldRecord might only
                // contain the ID. If the userId is missing, we assume the change
                // belongs to the currently authenticated user.
                final userId = item.userId.isNotEmpty
                    ? item.userId
                    : _client.auth.currentUser?.id;
                if (userId == null) {
                  talker.warning(
                      'Could not determine userId for change in table: $tableName, dropping event.');
                  return;
                }
                _streamController?.add(
                  DatumChangeDetail<T>(
                    type: type,
                    entityId: item.id,
                    userId: userId,
                    timestamp: item.modifiedAt,
                    data: item,
                  ),
                );
                talker.info(
                    'Successfully processed and streamed change for ${item.id} in table: $tableName');
              } else {
                talker.warning(
                    'Change event received for table: $tableName but not processed (type or record was null).');
              }
            },
          );

      talker.debug("Subscribing to channel for table: $tableName");
      _channel?.subscribe(
        (status, error) {
          talker.info(
              "Channel subscription status for table '$tableName': $status");
          if (error != null) {
            talker.error(
                "Channel subscription error for table '$tableName': $error");
            _handleSubscriptionError();
          } else if (status == RealtimeSubscribeStatus.subscribed) {
            talker.info(
                "Successfully subscribed to changes for table: $tableName");
            _onSubscriptionRestored();
          } else if (status == RealtimeSubscribeStatus.closed) {
            talker.warning("Channel closed for table: $tableName");
            _handleSubscriptionError();
          } else if (status == RealtimeSubscribeStatus.timedOut) {
            talker
                .error("Channel subscription timed out for table: $tableName");
            _handleSubscriptionError();
          } else if (status == RealtimeSubscribeStatus.channelError) {
            talker.error("Channel error occurred for table: $tableName");
            _handleSubscriptionError();
          }
        },
      );

      talker.debug("Channel subscription initiated for table: $tableName");
    } catch (e, stackTrace) {
      talker.error("Failed to subscribe to changes for table '$tableName': $e",
          stackTrace);
      _channel = null;
    }
  }

  @override
  Future<void> unsubscribeFromChanges() async {
    talker.debug("Unsubscribing from changes for table: $tableName");

    if (_channel != null) {
      talker.debug("Removing main channel for table: $tableName");
      await _client.removeChannel(_channel!);
      _channel = null;
      talker
          .info("Successfully unsubscribed from changes for table: $tableName");
    } else {
      talker.debug("No active channel to unsubscribe for table: $tableName");
    }

    // Unsubscribe from all related entity channels
    if (_relatedChannels.isNotEmpty) {
      talker.debug(
          "Cleaning up ${_relatedChannels.length} related channels for table: $tableName");
      for (final entry in _relatedChannels.entries) {
        await _client.removeChannel(entry.value);
        talker.debug("Removed related channel: ${entry.key}");
      }
      _relatedChannels.clear();
    }
  }

  @override
  Future<void> resubscribeToChanges() async {
    talker.info("Resubscribing to changes for table: $tableName");
    talker.debug(
        "Current channel state: ${_channel != null ? 'active' : 'null'}");

    try {
      await unsubscribeFromChanges();
      talker.debug(
          "Successfully unsubscribed, now subscribing again for table: $tableName");
      _subscribeToChanges();
      talker.info("Resubscription process completed for table: $tableName");
    } catch (e, stackTrace) {
      talker.error(
          "Failed to resubscribe to changes for table '$tableName': $e",
          stackTrace);
    }
  }

  Future<void> clearSyncMetadata(String userId) async {
    await _client.from(_metadataTableName).delete().eq('user_id', userId);
  }

  // Authentication monitoring methods
  void startAuthMonitoring() {
    if (_authSubscription != null) return; // Already monitoring

    talker.info(
        "Starting authentication state monitoring for $tableName adapter");
    _authSubscription = _client.auth.onAuthStateChange.listen(
      (AuthState authState) {
        final isAuthenticated = authState.session != null;
        _updateAuthenticationState(isAuthenticated);

        if (!isAuthenticated) {
          talker.info("User logged out, stopping sync for $tableName adapter");
          // Stop syncing when user logs out
          _retryManager.reset();
          unsubscribeFromChanges();
        } else {
          talker.info("User logged in, resuming sync for $tableName adapter");
          // Resume syncing when user logs in
          if (_channel == null) {
            _subscribeToChanges();
          }
        }
      },
      onError: (error) {
        talker.error("Auth state monitoring error: $error");
      },
    );

    // Set initial state
    final currentSession = _client.auth.currentSession;
    _updateAuthenticationState(currentSession != null);
  }

  Future<void> _stopAuthMonitoring() async {
    if (_authSubscription != null) {
      await _authSubscription!.cancel();
      _authSubscription = null;
      talker.info(
          "Stopped authentication state monitoring for $tableName adapter");
    }
  }

  void _updateAuthenticationState(bool isAuthenticated) {
    if (_isAuthenticated != isAuthenticated) {
      _isAuthenticated = isAuthenticated;
      _authStateController.add(isAuthenticated);
      talker.debug(
          "Authentication state changed: $isAuthenticated for $tableName adapter");
    }
  }

  // Subscription management
  void _handleSubscriptionError() {
    _retryManager.scheduleRetry(
        tableName, _isAuthenticated, _subscribeToChanges);
  }

  void _onSubscriptionRestored() {
    final hadFailures = _retryManager.hasFailures;
    _retryManager.reset();

    if (hadFailures) {
      talker.info(
          "Subscription restored for table: $tableName after failures. Triggering full sync to catch missed updates.");
      _triggerFullSyncAfterRestoration();
    } else {
      talker.debug(
          "Subscription restored for table: $tableName (no failures detected)");
    }
  }

  void _triggerFullSyncAfterRestoration() async {
    try {
      final currentUser = _client.auth.currentUser;
      if (currentUser == null) {
        talker.debug(
            "No authenticated user found, skipping restoration sync for table: $tableName");
        return;
      }

      // Check if Datum is initialized before attempting sync
      if (!Datum.isInitialized) {
        talker.debug(
            "Datum not initialized yet, skipping restoration sync for table: $tableName");
        return;
      }

      await Datum.manager<T>().synchronize(
        currentUser.id,
        options: DatumSyncOptions<T>(
          forceFullSync: true,
          direction: SyncDirection.pullOnly,
        ),
      );

      talker.info(
          "Successfully completed restoration sync for table: $tableName");
    } catch (e, stackTrace) {
      talker.error(
          "Failed to perform restoration sync for table: $tableName: $e",
          stackTrace);
    }
  }

  @override
  Future<void> dispose() async {
    _retryManager.dispose();
    await unsubscribeFromChanges();
    await _streamController?.close();
    await _stopAuthMonitoring();
    await _authStateController.close();
    return super.dispose();
  }

  @override
  Future<void> initialize() async {
    talker.info("Initializing SupabaseRemoteAdapter for table: $tableName");
    talker.debug(
        "Current channel state: ${_channel != null ? 'exists' : 'null'}");

    try {
      // Start monitoring authentication state FIRST
      talker.debug("Starting authentication monitoring for table: $tableName");
      startAuthMonitoring();

      // Wait a brief moment for auth state to stabilize
      await Future.delayed(const Duration(milliseconds: 100));

      // Only attempt subscription if authenticated
      if (_isAuthenticated && _channel == null) {
        talker.debug(
            "User is authenticated, ensuring clean state and subscribing for table: $tableName");
        await unsubscribeFromChanges();
        _subscribeToChanges();
      } else if (!_isAuthenticated) {
        talker.debug(
            "User not authenticated during initialization, subscription will be handled by auth monitoring for table: $tableName");
      } else {
        talker.debug(
            "Channel already exists for table: $tableName, skipping subscription during initialization");
      }

      talker.info(
          "Successfully initialized SupabaseRemoteAdapter for table: $tableName");
    } catch (e, stackTrace) {
      talker.error(
          "Failed to initialize SupabaseRemoteAdapter for table '$tableName': $e",
          stackTrace);
      rethrow;
    }

    // The Supabase client is initialized globally, so no specific
    // initialization is needed for this adapter instance.
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
    // The sync engine calls `update` for full-data updates.
    // We can use `upsert` to handle both creating and replacing the entity.
    // This is simpler and more robust than calculating a diff here.
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
          talker.warning('Unsupported query operator: ${condition.operator}');
      }
    } else if (condition is CompositeFilter) {
      // Note: Supabase PostgREST builder doesn't directly support nested OR/AND
      // in this fluent way. This is a simplified implementation. For complex
      // nested logic, you might need to use `rpc` calls to database functions.
      final filters = condition.conditions.map((c) {
        // This is a simplified conversion and might not work for all cases.
        return '${(c as Filter).field.snakeCase}.${(c).operator.name}.${c.value}';
      }).join(',');
      return builder.filter(condition.operator.name, 'any', filters);
    }
    return builder;
  }

  @override
  Future<List<R>> fetchRelated<R extends DatumEntityInterface>(
    RelationalDatumEntity parent,
    String relationName,
    RemoteAdapter<R> relatedAdapter,
  ) async {
    final relatedSupabaseAdapter = relatedAdapter as SupabaseRemoteAdapter<R>;
    final relatedTableName = relatedSupabaseAdapter.tableName;

    PostgrestFilterBuilder queryBuilder =
        _client.from(relatedTableName).select();

    final relation = parent.relations[relationName];

    switch (relation) {
      case BelongsTo(:var foreignKey, :var localKey):
        final relatedKeyValue = parent.toDatumMap()[localKey];
        if (relatedKeyValue == null) {
          return [];
        }
        queryBuilder = queryBuilder.eq(foreignKey.snakeCase, relatedKeyValue);
        break;
      case HasMany(:final foreignKey, :final localKey):
      case HasOne(:final foreignKey, :final localKey):
        // The foreign key is in the related table, pointing to the parent.
        final foreignKeyColumn = foreignKey.snakeCase;
        final localKeyValue = parent.toDatumMap()[localKey];
        if (localKeyValue == null) {
          return [];
        }
        queryBuilder = queryBuilder.eq(foreignKeyColumn, localKeyValue);
        break;
      case ManyToMany(
          :final otherForeignKey,
          :final otherLocalKey,
          :final thisForeignKey,
          :final thisLocalKey,
        ):
        // Get the pivot table name from the pivot entity
        final pivotAdapter = Datum.manager().remoteAdapter;
        if (pivotAdapter is! SupabaseRemoteAdapter) {
          throw ArgumentError('Pivot adapter must be a SupabaseRemoteAdapter');
        }
        final pivotTableName = pivotAdapter.tableName;

        // Get parent ID
        final parentIdValue = parent.toDatumMap()[thisLocalKey];
        if (parentIdValue == null) {
          return [];
        }

        // Query the junction table to find the IDs of related entities
        final junctionRecords = await _client
            .from(pivotTableName)
            .select(otherForeignKey.snakeCase)
            .eq(thisForeignKey.snakeCase, parentIdValue);

        if (junctionRecords.isEmpty) {
          return [];
        }

        // Extract the IDs of the related entities
        final relatedIds = junctionRecords
            .map((record) => record[otherForeignKey.snakeCase])
            .whereType<String>()
            .toList();

        if (relatedIds.isEmpty) {
          return [];
        }

        // Query the related table using the extracted IDs
        queryBuilder =
            queryBuilder.inFilter(otherLocalKey.snakeCase, relatedIds);
        break;
      case null:
        throw ArgumentError(
            'Relation "$relationName" not found for parent entity.');
    }

    final response = await queryBuilder;

    return response
        .map<R>((json) => relatedSupabaseAdapter.fromMap(_toCamelCase(json)))
        .toList();
  }

  Stream<List<R>> watchRelated<R extends DatumEntityInterface>(
    RelationalDatumEntity parent,
    String relationName,
    RemoteAdapter<R> relatedAdapter,
  ) {
    final relatedSupabaseAdapter = relatedAdapter as SupabaseRemoteAdapter<R>;
    final relatedTableName = relatedSupabaseAdapter.tableName;
    final relation = parent.relations[relationName];

    if (relation == null) {
      throw ArgumentError(
          'Relation "$relationName" not found for parent entity.');
    }

    // Create a stream controller for this relationship
    late StreamController<List<R>> controller;
    RealtimeChannel? channel;

    Future<void> fetchAndEmit() async {
      try {
        final items =
            await fetchRelated<R>(parent, relationName, relatedAdapter);
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
      final channelName =
          'related:$relatedTableName:${parent.id}:$relationName';

      channel = _client.channel(channelName).onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: relatedTableName,
            callback: (payload) {
              talker
                  .info('Related entity change detected in $relatedTableName');

              // Re-fetch and emit updated data when changes occur
              fetchAndEmit();
            },
          );

      // For ManyToMany relationships, also watch the pivot table
      if (relation is ManyToMany) {
        final pivotAdapter = Datum.manager().remoteAdapter;
        if (pivotAdapter is SupabaseRemoteAdapter) {
          final pivotTableName = pivotAdapter.tableName;
          final pivotChannelName =
              'pivot:$pivotTableName:${parent.id}:$relationName';

          final pivotChannel = _client
              .channel(pivotChannelName)
              .onPostgresChanges(
                event: PostgresChangeEvent.all,
                schema: 'public',
                table: pivotTableName,
                callback: (payload) {
                  talker.info('Pivot table change detected in $pivotTableName');
                  fetchAndEmit();
                },
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
        // Fetch initial data
        fetchAndEmit();

        // Setup realtime subscription
        setupRealtimeSubscription();
      },
      onCancel: () async {
        if (channel != null) {
          await _client.removeChannel(channel!);
          _relatedChannels
              .remove('related:$relatedTableName:${parent.id}:$relationName');
        }

        // Clean up pivot channel if it exists
        if (relation is ManyToMany) {
          final pivotAdapter = Datum.manager().remoteAdapter;
          if (pivotAdapter is SupabaseRemoteAdapter) {
            final pivotTableName = pivotAdapter.tableName;
            final pivotChannelName =
                'pivot:$pivotTableName:${parent.id}:$relationName';
            final pivotChannel = _relatedChannels[pivotChannelName];
            if (pivotChannel != null) {
              await _client.removeChannel(pivotChannel);
              _relatedChannels.remove(pivotChannelName);
            }
          }
        }
      },
    );

    return controller.stream;
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

## Usage Example

```dart
import 'supabase_remote_adapter.dart'; // the adapter implemented above

// Create the adapter
final taskAdapter = SupabaseRemoteAdapter<Task>(
  tableName: 'tasks',
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

## Supabase RLS Policies

Set up Row Level Security policies for your Supabase tables:

### Tasks Table
```sql
-- Enable RLS
ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;

-- Users can only access their own tasks
CREATE POLICY "Users can view own tasks" ON tasks
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own tasks" ON tasks
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own tasks" ON tasks
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own tasks" ON tasks
  FOR DELETE USING (auth.uid() = user_id);
```

### Sync Metadata Table
```sql
-- Enable RLS
ALTER TABLE sync_metadata ENABLE ROW LEVEL SECURITY;

-- Users can only access their own sync metadata
CREATE POLICY "Users can view own sync metadata" ON sync_metadata
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own sync metadata" ON sync_metadata
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own sync metadata" ON sync_metadata
  FOR UPDATE USING (auth.uid() = user_id);
```

## Database Schema

Create the necessary tables in your Supabase database:

```sql
-- Tasks table
CREATE TABLE tasks (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  description TEXT,
  completed BOOLEAN DEFAULT FALSE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  modified_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Sync metadata table
CREATE TABLE sync_metadata (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE UNIQUE,
  last_sync_time TIMESTAMP WITH TIME ZONE,
  schema_version INTEGER DEFAULT 1,
  device_id TEXT,
  total_pending_changes INTEGER DEFAULT 0,
  conflict_count INTEGER DEFAULT 0,
  sync_status TEXT DEFAULT 'never_synced',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for better performance
CREATE INDEX idx_tasks_user_id ON tasks(user_id);
CREATE INDEX idx_tasks_modified_at ON tasks(modified_at);
CREATE INDEX idx_sync_metadata_user_id ON sync_metadata(user_id);

-- Enable Row Level Security
ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE sync_metadata ENABLE ROW LEVEL SECURITY;
