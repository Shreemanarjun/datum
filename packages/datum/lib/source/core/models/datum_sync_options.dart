import 'package:datum/source/core/query/datum_query.dart';
import 'package:datum/source/core/resolver/conflict_resolution.dart';
import 'package:datum/source/core/models/datum_entity.dart';
import 'package:meta/meta.dart';

/// Defines the order of operations during a synchronization cycle.
enum SyncDirection {
  /// Push local changes first, then pull remote changes. An unsynced edit is
  /// uploaded before this device looks at the remote row, so it replaces an
  /// edit another device uploaded meanwhile: the last push wins, and no
  /// resolver is asked on this device.
  pushThenPull,

  /// Pull remote changes first, then push local changes. This is the
  /// default: an unsynced edit of a row that changed remotely is a conflict
  /// the resolver decides before anything is overwritten.
  pullThenPush,

  /// Only push local changes to the remote.
  pushOnly,

  /// Only pull remote changes to local.
  pullOnly,
}

/// Configuration passed when triggering a manual synchronization via `Datum.sync()`.
@immutable
class DatumSyncOptions<T extends DatumEntityInterface> {
  /// Whether this cycle syncs deletions. When false, queued delete
  /// operations stay queued (with any later ops for the same entity, to keep
  /// order) and remote-deletion detection is skipped.
  final bool includeDeletes;

  /// Whether conflicts found while pulling are resolved with the configured
  /// resolver. When false they are only reported (`ConflictDetectedEvent`);
  /// the local row and its queued operations are left untouched.
  final bool resolveConflicts;

  /// If true, forces a full pull of all remote data: the "nothing changed"
  /// metadata shortcut is skipped and delta/cursor adapters are asked for
  /// everything (`readAll`) instead of changes since the last sync.
  final bool forceFullSync;

  /// A custom batch size for this sync, overriding the one in [DatumConfig].
  final int? overrideBatchSize;

  /// A timeout for this specific sync operation, overriding the one in[DatumConfig] .
  final Duration? timeout;

  /// The order of synchronization operations for this sync, overriding the default.
  final SyncDirection? direction;

  /// A conflict resolver to override the default for this sync only.
  final DatumConflictResolver<T>? conflictResolver;

  /// A query used to filter the data fetched from the remote source.
  /// The interpretation of this query is up to the `RemoteAdapter` implementation.
  final DatumQuery query;

  /// Creates sync options to customize a manual sync cycle.
  const DatumSyncOptions({
    this.includeDeletes = true,
    this.resolveConflicts = true,
    this.forceFullSync = false,
    this.overrideBatchSize,
    this.timeout,
    this.direction,
    this.conflictResolver,
    this.query = const DatumQuery(),
    this.reason,
  });

  /// Why this sync runs — a free-form tag for logs and telemetry, reported in
  /// `DatumSyncStartedEvent.reason`. Syncs the engine starts itself use
  /// `auto`, `after-write`, `retry`, `retry-after` and `sign-in`.
  final String? reason;

  /// These options for entity type [E]. The per-sync resolver is kept only
  /// when it can resolve [E].
  DatumSyncOptions<E> retype<E extends DatumEntityInterface>() => DatumSyncOptions<E>(
        includeDeletes: includeDeletes,
        resolveConflicts: resolveConflicts,
        forceFullSync: forceFullSync,
        overrideBatchSize: overrideBatchSize,
        timeout: timeout,
        direction: direction,
        conflictResolver: switch (conflictResolver) { final DatumConflictResolver<E> resolver => resolver, _ => null },
        query: query,
        reason: reason,
      );

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
    DatumQuery? query,
    String? reason,
  }) {
    return DatumSyncOptions<T>(
      includeDeletes: includeDeletes ?? this.includeDeletes,
      resolveConflicts: resolveConflicts ?? this.resolveConflicts,
      forceFullSync: forceFullSync ?? this.forceFullSync,
      overrideBatchSize: overrideBatchSize ?? this.overrideBatchSize,
      timeout: timeout ?? this.timeout,
      direction: direction ?? this.direction,
      conflictResolver: conflictResolver ?? this.conflictResolver,
      query: query ?? this.query,
      reason: reason ?? this.reason,
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
        other.conflictResolver == conflictResolver &&
        other.query == query &&
        other.reason == reason;
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
      query,
      reason,
    );
  }
}
