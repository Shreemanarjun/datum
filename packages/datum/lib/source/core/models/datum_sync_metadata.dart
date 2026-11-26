import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

/// Describes the synchronization state for a single entity type.
@immutable
class DatumEntitySyncDetails {
  /// Creates details for an entity's sync state.
  const DatumEntitySyncDetails({
    required this.count,
    this.hash,
    this.lastModified,
    this.pendingChanges = 0,
  });

  /// Creates [DatumEntitySyncDetails] from a map (JSON).
  factory DatumEntitySyncDetails.fromJson(Map<String, dynamic> json) {
    return DatumEntitySyncDetails(
      count: json['count'] as int,
      hash: json['hash'] as String?,
      lastModified: json['lastModified'] != null ? DateTime.parse(json['lastModified'] as String) : null,
      pendingChanges: json['pendingChanges'] as int? ?? 0,
    );
  }

  /// The total number of items for this entity.
  final int count;

  /// An optional hash of this entity's data for integrity checking.
  final String? hash;

  /// Last modification time for this entity type.
  final DateTime? lastModified;

  /// Number of pending changes waiting to be synced.
  final int pendingChanges;

  /// Converts to a map for JSON serialization.
  Map<String, dynamic> toMap() => {
        'count': count,
        if (hash != null) 'hash': hash,
        if (lastModified != null) 'lastModified': lastModified!.toUtc().toIso8601String(),
        'pendingChanges': pendingChanges,
      };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is DatumEntitySyncDetails && other.count == count && other.hash == hash && other.lastModified == lastModified && other.pendingChanges == pendingChanges;
  }

  @override
  int get hashCode => Object.hash(count, hash, lastModified, pendingChanges);

  @override
  String toString() => 'DatumEntitySyncDetails(count: $count, hash: $hash, lastModified: $lastModified, pendingChanges: $pendingChanges)';
}

/// Sync status enumeration.
enum SyncStatus {
  /// Never synced before.
  neverSynced,

  /// Currently syncing.
  syncing,

  /// Last sync completed successfully.
  synced,

  /// Last sync failed.
  failed,

  /// Sync is pending/queued.
  pending,

  /// Conflicts detected.
  conflict,
}

/// Metadata describing the synchronization state for a specific user.
///
/// Below is the schema for the `sync_metadata` table in Supabase/PostgreSQL.
///
/// ```sql
/// CREATE TABLE public.sync_metadata (
///   user_id text NOT NULL,
///   last_sync_time text NULL,
///   last_successful_sync_time text NULL,
///   data_hash text NULL,
///   device_id text NULL,
///   devices text NULL,
///   custom_metadata jsonb NULL,
///   entity_counts jsonb NULL,
///   sync_status text NOT NULL DEFAULT 'pending'::text,
///   sync_version integer NOT NULL DEFAULT 0,
///   server_timestamp text NULL,
///   conflict_count integer NOT NULL DEFAULT 0,
///   error_message text NULL,
///   retry_count integer NOT NULL DEFAULT 0,
///   sync_duration integer NULL,
///   created_at timestamp with time zone NOT NULL DEFAULT now(),
///   updated_at timestamp with time zone NOT NULL DEFAULT now(),
///   CONSTRAINT sync_metadata_pkey PRIMARY KEY (user_id)
/// ) TABLESPACE pg_default;
/// ```
///
/// Note: The `devices` and `entity_counts` fields are stored as JSON strings in the database
/// but parsed into structured Dart objects (`Map<String, DateTime>` and `Map<String, DatumEntitySyncDetails>` respectively).
@immutable
class DatumSyncMetadata extends Equatable {
  /// Helper method to get a value from a map that may contain either camelCase or snake_case keys.
  /// Returns the value for the first matching key found, preferring camelCase over snake_case.
  static T? getValueFromMap<T>(
    Map<String, dynamic> map,
    String camelCaseKey,
    String snakeCaseKey, {
    T? defaultValue,
  }) {
    return (map[camelCaseKey] ?? map[snakeCaseKey]) as T? ?? defaultValue;
  }

  /// Helper method to get a required value from a map that may contain either camelCase or snake_case keys.
  /// Throws a [FormatException] if the key is not found.
  static T getRequiredValueFromMap<T>(
    Map<String, dynamic> map,
    String camelCaseKey,
    String snakeCaseKey,
  ) {
    final value = map[camelCaseKey] ?? map[snakeCaseKey];
    if (value == null) {
      throw FormatException('Required field "$camelCaseKey" is missing from map');
    }
    return value as T;
  }

  /// Creates sync metadata.
  const DatumSyncMetadata({
    required this.userId,
    this.lastSyncTime,
    this.lastSuccessfulSyncTime,
    this.dataHash,
    this.deviceId,
    this.devices,
    this.customMetadata,
    this.entityCounts,
    this.syncStatus = SyncStatus.neverSynced,
    this.syncVersion = 1,
    this.serverTimestamp,
    this.conflictCount = 0,
    this.errorMessage,
    this.retryCount = 0,
    this.syncDuration,
  });

  /// Creates SyncMetadata from JSON.
  /// Supports both camelCase (Dart convention) and snake_case (database convention) keys.
  factory DatumSyncMetadata.fromMap(Map<String, dynamic> json) {
    try {
      dynamic getValue(String camelKey, String snakeKey) => json[camelKey] ?? json[snakeKey];
      final userId = getValue('userId', 'user_id');
      if (userId == null) {
        throw const FormatException('Required field "userId" is missing from sync metadata');
      }

      return DatumSyncMetadata(
        userId: userId as String,
        lastSyncTime: _parseDateTime(getValue('lastSyncTime', 'last_sync_time')),
        lastSuccessfulSyncTime: _parseDateTime(getValue('lastSuccessfulSyncTime', 'last_successful_sync_time')),
        dataHash: getValue('dataHash', 'data_hash') as String?,
        deviceId: getValue('deviceId', 'device_id') as String?,
        devices: _parseDevices(getValue('devices', 'devices')),
        customMetadata: getValue('customMetadata', 'custom_metadata') as Map<String, dynamic>?,
        entityCounts: _parseEntityCounts(getValue('entityCounts', 'entity_counts')),
        syncStatus: _parseSyncStatus(getValue('syncStatus', 'sync_status')),
        syncVersion: getValue('syncVersion', 'sync_version') as int? ?? 1,
        serverTimestamp: _parseDateTime(getValue('serverTimestamp', 'server_timestamp')),
        conflictCount: getValue('conflictCount', 'conflict_count') as int? ?? 0,
        errorMessage: getValue('errorMessage', 'error_message') as String?,
        retryCount: getValue('retryCount', 'retry_count') as int? ?? 0,
        syncDuration: getValue('syncDuration', 'sync_duration') as int?,
      );
    } catch (e) {
      throw FormatException('Failed to parse DatumSyncMetadata: $e');
    }
  }

  /// User ID for this metadata.
  final String userId;

  /// Timestamp of last synchronization attempt (successful or not).
  final DateTime? lastSyncTime;

  /// Timestamp of last successful synchronization.
  final DateTime? lastSuccessfulSyncTime;

  /// An optional global hash of all data for high-level integrity checking.
  final String? dataHash;

  /// Current device identifier.
  final String? deviceId;

  /// Map of all devices that have synced, with their last sync time.
  final Map<String, DateTime>? devices;

  /// Custom metadata fields.
  final Map<String, dynamic>? customMetadata;

  /// A map of counts for different entity types, allowing tracking of multiple
  /// "tables" or data collections.
  final Map<String, DatumEntitySyncDetails>? entityCounts;

  /// Current synchronization status.
  final SyncStatus syncStatus;

  /// Version number for sync protocol compatibility.
  final int syncVersion;

  /// Server-side timestamp for consistency.
  final DateTime? serverTimestamp;

  /// Number of conflicts detected during last sync.
  final int conflictCount;

  /// Error message from last failed sync.
  final String? errorMessage;

  /// Number of retry attempts for failed sync.
  final int retryCount;

  /// Duration of last sync in milliseconds.
  final int? syncDuration;

  /// Whether a sync is currently in progress.
  bool get isSyncing => syncStatus == SyncStatus.syncing;

  /// Whether the last sync was successful.
  bool get isLastSyncSuccessful => syncStatus == SyncStatus.synced;

  /// Whether there are conflicts.
  bool get hasConflicts => conflictCount > 0;

  /// Whether sync has never occurred.
  bool get isNeverSynced => syncStatus == SyncStatus.neverSynced;

  /// Total pending changes across all entities.
  int get totalPendingChanges {
    if (entityCounts == null) return 0;
    return entityCounts!.values.fold(
      0,
      (sum, entity) => sum + entity.pendingChanges,
    );
  }

  /// Get all device IDs that have synced.
  List<String> get allDeviceIds {
    if (devices == null) return deviceId != null ? [deviceId!] : [];
    return devices!.keys.toList();
  }

  /// Get the count of devices.
  int get deviceCount {
    if (devices == null) return deviceId != null ? 1 : 0;
    return devices!.length;
  }

  /// Get last sync time for a specific device.
  DateTime? getDeviceLastSync(String deviceId) {
    return devices?[deviceId];
  }

  /// Check if a specific device has synced.
  bool hasDeviceSynced(String deviceId) {
    return devices?.containsKey(deviceId) ?? false;
  }

  /// Creates a copy with modified fields.
  DatumSyncMetadata copyWith({
    DateTime? lastSyncTime,
    DateTime? lastSuccessfulSyncTime,
    String? dataHash,
    String? deviceId,
    Map<String, DateTime>? devices,
    Map<String, dynamic>? customMetadata,
    Map<String, DatumEntitySyncDetails>? entityCounts,
    SyncStatus? syncStatus,
    int? syncVersion,
    DateTime? serverTimestamp,
    int? conflictCount,
    String? errorMessage,
    int? retryCount,
    int? syncDuration,
  }) {
    return DatumSyncMetadata(
      userId: userId,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      lastSuccessfulSyncTime: lastSuccessfulSyncTime ?? this.lastSuccessfulSyncTime,
      dataHash: dataHash ?? this.dataHash,
      deviceId: deviceId ?? this.deviceId,
      devices: devices ?? this.devices,
      customMetadata: customMetadata ?? this.customMetadata,
      entityCounts: entityCounts ?? this.entityCounts,
      syncStatus: syncStatus ?? this.syncStatus,
      syncVersion: syncVersion ?? this.syncVersion,
      serverTimestamp: serverTimestamp ?? this.serverTimestamp,
      conflictCount: conflictCount ?? this.conflictCount,
      errorMessage: errorMessage ?? this.errorMessage,
      retryCount: retryCount ?? this.retryCount,
      syncDuration: syncDuration ?? this.syncDuration,
    );
  }

  /// Creates metadata marking sync as started.
  DatumSyncMetadata markSyncStarted() {
    return copyWith(
      lastSyncTime: DateTime.now(),
      syncStatus: SyncStatus.syncing,
      errorMessage: null,
    );
  }

  /// Creates metadata marking sync as completed successfully.
  DatumSyncMetadata markSyncCompleted({
    String? dataHash,
    Map<String, DatumEntitySyncDetails>? entityCounts,
    DateTime? serverTimestamp,
    int? syncDuration,
  }) {
    final now = DateTime.now();
    final updatedDevices = Map<String, DateTime>.from(devices ?? {});
    if (deviceId != null) {
      updatedDevices[deviceId!] = now;
    }

    return copyWith(
      lastSuccessfulSyncTime: now,
      syncStatus: SyncStatus.synced,
      dataHash: dataHash,
      entityCounts: entityCounts,
      serverTimestamp: serverTimestamp,
      devices: updatedDevices,
      conflictCount: 0,
      errorMessage: null,
      retryCount: 0,
      syncDuration: syncDuration,
    );
  }

  /// Creates metadata marking sync as failed.
  DatumSyncMetadata markSyncFailed({
    required String errorMessage,
    bool incrementRetry = true,
  }) {
    return copyWith(
      syncStatus: SyncStatus.failed,
      errorMessage: errorMessage,
      retryCount: incrementRetry ? retryCount + 1 : retryCount,
    );
  }

  /// Creates metadata marking conflicts detected.
  DatumSyncMetadata markConflicts(int conflictCount) {
    return copyWith(
      syncStatus: SyncStatus.conflict,
      conflictCount: conflictCount,
    );
  }

  /// Converts to a map.
  Map<String, dynamic> toMap() => {
        'userId': userId,
        if (lastSyncTime != null) 'lastSyncTime': lastSyncTime!.toUtc().toIso8601String(),
        if (lastSuccessfulSyncTime != null) 'lastSuccessfulSyncTime': lastSuccessfulSyncTime!.toUtc().toIso8601String(),
        if (dataHash != null) 'dataHash': dataHash,
        if (deviceId != null) 'deviceId': deviceId,
        if (devices != null)
          'devices': devices!.map(
            (key, value) => MapEntry(key, value.toUtc().toIso8601String()),
          ),
        if (customMetadata != null) 'customMetadata': customMetadata,
        if (entityCounts != null)
          'entityCounts': entityCounts!.map(
            (key, value) => MapEntry(key, value.toMap()),
          ),
        'syncStatus': syncStatus.toString().split('.').last,
        'syncVersion': syncVersion,
        if (serverTimestamp != null) 'serverTimestamp': serverTimestamp!.toUtc().toIso8601String(),
        'conflictCount': conflictCount,
        if (errorMessage != null) 'errorMessage': errorMessage,
        'retryCount': retryCount,
        if (syncDuration != null) 'syncDuration': syncDuration,
      };

  @override
  List<Object?> get props => [
        userId,
        lastSyncTime,
        lastSuccessfulSyncTime,
        dataHash,
        deviceId,
        devices,
        customMetadata,
        entityCounts,
        syncStatus,
        syncVersion,
        serverTimestamp,
        conflictCount,
        errorMessage,
        retryCount,
        syncDuration,
      ];
}

DateTime? _parseDateTime(dynamic value) {
  if (value == null) return null;
  if (value is! String) {
    throw FormatException('Date field must be a string, got: ${value.runtimeType}');
  }
  try {
    return DateTime.parse(value);
  } catch (e) {
    throw FormatException('Invalid date format for field: $value');
  }
}

Map<String, DateTime>? _parseDevices(dynamic devicesValue) {
  if (devicesValue == null) return null;
  if (devicesValue is! Map<String, dynamic>) {
    throw FormatException('Devices field must be a map, got: ${devicesValue.runtimeType}');
  }
  return devicesValue.map((key, value) {
    try {
      return MapEntry(key, DateTime.parse(value as String));
    } catch (e) {
      throw FormatException('Invalid date format in devices map for key "$key": $value');
    }
  });
}

Map<String, DatumEntitySyncDetails>? _parseEntityCounts(dynamic entityCountsValue) {
  if (entityCountsValue == null) return null;
  if (entityCountsValue is! Map<String, dynamic>) {
    throw FormatException('Entity counts field must be a map, got: ${entityCountsValue.runtimeType}');
  }
  return entityCountsValue.map((key, value) {
    try {
      return MapEntry(key, DatumEntitySyncDetails.fromJson(value as Map<String, dynamic>));
    } catch (e) {
      throw FormatException('Invalid entity counts format for key "$key": $e');
    }
  });
}

SyncStatus _parseSyncStatus(dynamic statusValue) {
  if (statusValue == null) return SyncStatus.neverSynced;
  if (statusValue is! String) {
    throw FormatException('Sync status must be a string, got: ${statusValue.runtimeType}');
  }
  return SyncStatus.values.firstWhere(
    (e) => e.toString() == 'SyncStatus.$statusValue',
    orElse: () => SyncStatus.neverSynced,
  );
}
