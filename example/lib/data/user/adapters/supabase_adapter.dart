import 'dart:async';

import 'package:datum/datum.dart';
import 'package:example/bootstrap.dart';
import 'package:recase/recase.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseRemoteAdapter<T extends DatumEntity> extends RemoteAdapter<T> {
  final String tableName;
  final T Function(Map<String, dynamic>) fromMap;

  SupabaseRemoteAdapter({
    required this.tableName,
    required this.fromMap,
  });

  RealtimeChannel? _channel;
  StreamController<DatumChangeDetail<T>>? _streamController;

  SupabaseClient get _client => Supabase.instance.client;
  String get _metadataTableName => 'sync_metadata';

  @override
  Future<void> delete(String id, {String? userId}) async {
    await _client.from(tableName).delete().eq(
          'id',
          id,
        );
  }

  @override
  Future<List<T>> readAll({String? userId, DatumSyncScope? scope}) async {
    // Note: The 'scope' parameter is not used in this implementation.
    // You can extend this to support scoped fetching if needed.
    final response =
        await _client.from(tableName).select().eq('user_id', userId ?? '');
    return response.map<T>((json) => fromMap(_toCamelCase(json))).toList();
  }

  @override
  Future<T?> read(String id, {String? userId}) async {
    final response =
        await _client.from(tableName).select().eq('id', id).maybeSingle();

    if (response == null) {
      return null;
    }
    return fromMap(_toCamelCase(response));
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
  Future<bool> isConnected() async {
    // Supabase client does not have a direct connectivity check.
    // This is usually handled by a separate connectivity package.
    // For this implementation, we assume the Datum's connectivityChecker handles it.
    return true;
  }

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
    final snakeCaseDelta = _toSnakeCase(delta);
    final response = await _client
        .from(tableName)
        .update(snakeCaseDelta)
        .eq('id', id)
        .select()
        .maybeSingle();
    if (response == null) {
      throw EntityNotFoundException(
        'Failed to patch item: record not found or RLS policy prevented selection.',
      );
    }
    return fromMap(_toCamelCase(response));
  }

  @override
  Future<void> updateSyncMetadata(
      DatumSyncMetadata metadata, String userId) async {
    talker
        .debug("Updating sync metadata for user: $userId with data: $metadata");
    final data = _toSnakeCase(metadata.toMap());
    data['user_id'] = userId;

    await _client.from(_metadataTableName).upsert(
          data,
          onConflict: 'user_id',
        );
  }

  @override
  Stream<DatumChangeDetail<T>>? get changeStream {
    _streamController ??= StreamController<DatumChangeDetail<T>>.broadcast(
      onListen: _subscribeToChanges,
      onCancel: _unsubscribeFromChanges,
    );
    return _streamController?.stream;
  }

  void _subscribeToChanges() {
    talker.info("Subscribing to Supabase changes for table: $tableName");
    _channel = _client
        .channel(
          'public:$tableName',
          opts: const RealtimeChannelConfig(self: false),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: tableName,
          callback: (payload) {
            talker.info('Received Supabase change: ${payload.eventType}');
            talker.debug('Payload: $payload');

            DatumOperationType? type;
            Map<String, dynamic>? record;

            switch (payload.eventType) {
              case PostgresChangeEvent.insert:
                type = DatumOperationType.create;
                record = payload.newRecord;
                talker.debug('Insert event detected.');
                break;
              case PostgresChangeEvent.update:
                type = DatumOperationType.update;
                record = payload.newRecord;
                talker.debug('Update event detected.');
                break;
              case PostgresChangeEvent.delete:
                type = DatumOperationType.delete;
                record = payload.oldRecord;
                talker.debug('Delete event detected.');
                break;
              case PostgresChangeEvent.all:
                talker.debug('Received "all" event type, ignoring.');
                break;
            }

            if (type != null && record != null) {
              talker
                  .debug('Processing change of type $type for record: $record');
              final item = fromMap(_toCamelCase(record));
              // When a delete event comes from Supabase, the oldRecord might only
              // contain the ID. If the userId is missing, we assume the change
              // belongs to the currently authenticated user.
              final userId = item.userId.isNotEmpty
                  ? item.userId
                  : _client.auth.currentUser?.id;
              if (userId == null) {
                talker.warning(
                    'Could not determine userId for change, dropping event.');
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
                  'Successfully processed and streamed change for ${item.id}');
            } else {
              talker.warning(
                  'Change event received but not processed (type or record was null).');
            }
          },
        )..subscribe();
  }

  void _unsubscribeFromChanges() {
    if (_channel != null) {
      _client.removeChannel(_channel!);
      _channel = null;
    }
  }

  Future<void> clearSyncMetadata(String userId) async {
    await _client.from(_metadataTableName).delete().eq('user_id', userId);
  }

  @override
  Future<void> initialize() {
    // The Supabase client is initialized globally, so no specific
    // initialization is needed for this adapter instance.
    return Future.value();
  }

  @override
  Future<List<T>> query(DatumQuery query, {String? userId}) async {
    PostgrestFilterBuilder queryBuilder = _client.from(tableName).select();

    if (userId != null) {
      queryBuilder = queryBuilder.eq('user_id', userId);
    }

    for (final condition in query.filters) {
      if (condition is Filter) {
        final field = condition.field.snakeCase;
        final value = condition.value;

        switch (condition.operator) {
          case FilterOperator.equals:
            queryBuilder = queryBuilder.eq(field, value);
            break;
          case FilterOperator.notEquals:
            queryBuilder = queryBuilder.neq(field, value);
            break;
          case FilterOperator.lessThan:
            queryBuilder = queryBuilder.lt(field, value);
            break;
          case FilterOperator.lessThanOrEqual:
            queryBuilder = queryBuilder.lte(field, value);
            break;
          case FilterOperator.greaterThan:
            queryBuilder = queryBuilder.gt(field, value);
            break;
          case FilterOperator.greaterThanOrEqual:
            queryBuilder = queryBuilder.gte(field, value);
            break;
          case FilterOperator.arrayContains:
            queryBuilder = queryBuilder.contains(field, value);
            break;
          case FilterOperator.isIn:
            queryBuilder = queryBuilder.inFilter(field, value as List);
            break;
          default:
            talker.warning('Unsupported query operator: ${condition.operator}');
        }
      }
    }

    final response = await queryBuilder;

    return response.map<T>((json) => fromMap(_toCamelCase(json))).toList();
  }

  @override
  Future<void> update(T entity) async {
    // To perform a diff update, we need the previous version of the entity.
    // We'll fetch it from the local adapter.
    final localAdapter = Datum.manager<T>().localAdapter;
    final oldEntity = await localAdapter.read(entity.id, userId: entity.userId);

    Map<String, dynamic>? delta;
    if (oldEntity != null) {
      // Calculate the difference between the new and old entity.
      delta = entity.diff(oldEntity);
    } else {
      // If the old entity doesn't exist locally, send the full entity.
      talker.warning(
          'Old version of ${entity.id} not found locally. Performing a full update.');
      delta = entity.toDatumMap(target: MapTarget.remote);
    }

    if (delta == null || delta.isEmpty) {
      talker.info('No changes detected for ${entity.id}. Skipping update.');
      return;
    }

    // Use the existing patch method to send only the changed data.
    await patch(id: entity.id, delta: delta, userId: entity.userId);
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
