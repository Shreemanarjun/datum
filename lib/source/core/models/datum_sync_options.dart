import 'package:datum/source/config/datum_config.dart';
import 'package:datum/source/core/resolver/conflict_resolution.dart';
import 'package:datum/source/core/models/datum_entity.dart';
import 'package:meta/meta.dart';

/// Configuration passed when triggering a manual synchronization via `Datum.sync()`.
@immutable
class DatumSyncOptions<T extends DatumEntityBase> {
  /// Whether to include delete operations in the sync.
  final bool includeDeletes;

  /// Whether to automatically resolve conflicts using the configured resolver.
  final bool resolveConflicts;

  /// If true, forces a full pull of all remote data, ignoring local metadata.
  final bool forceFullSync;

  /// A custom batch size for this sync, overriding the one in `DatumConfig`.
  final int? overrideBatchSize;

  /// A timeout for this specific sync operation, overriding the one in `DatumConfig`.
  final Duration? timeout;

  /// The order of synchronization operations for this sync, overriding the default.
  final SyncDirection? direction;

  /// A conflict resolver to override the default for this sync only.
  final DatumConflictResolver<T>? conflictResolver;

  /// Creates sync options to customize a manual sync cycle.
  const DatumSyncOptions({
    this.includeDeletes = true,
    this.resolveConflicts = true,
    this.forceFullSync = false,
    this.overrideBatchSize,
    this.timeout,
    this.direction,
    this.conflictResolver,
  });

  /// Creates a new instance with the specified values, allowing for a change
  /// in the generic type.
  DatumSyncOptions<T> copyWith({
    bool? includeDeletes,
    bool? resolveConflicts,
    bool? forceFullSync,
    int? overrideBatchSize,
    Duration? timeout,
    SyncDirection? direction,
    DatumConflictResolver<T>? conflictResolver,
  }) {
    return DatumSyncOptions<T>(
      includeDeletes: includeDeletes ?? this.includeDeletes,
      resolveConflicts: resolveConflicts ?? this.resolveConflicts,
      forceFullSync: forceFullSync ?? this.forceFullSync,
      overrideBatchSize: overrideBatchSize ?? this.overrideBatchSize,
      timeout: timeout ?? this.timeout,
      direction: direction ?? this.direction,
      conflictResolver: conflictResolver ?? this.conflictResolver,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is DatumSyncOptions<T> &&
        other.includeDeletes == includeDeletes &&
        other.resolveConflicts == resolveConflicts &&
        other.forceFullSync == forceFullSync &&
        other.overrideBatchSize == overrideBatchSize &&
        other.timeout == timeout &&
        other.direction == direction &&
        other.conflictResolver == conflictResolver;
  }

  @override
  int get hashCode {
    return Object.hash(
      includeDeletes,
      resolveConflicts,
      forceFullSync,
      overrideBatchSize,
      timeout,
      direction,
      conflictResolver,
    );
  }
}
