import 'package:datum/source/core/models/conflict_context.dart';
import 'package:datum/source/core/models/user_switch_models.dart';
import 'package:datum/source/core/resolver/conflict_resolution.dart';
import 'package:datum/source/core/models/datum_entity.dart';
import 'package:datum/source/core/models/datum_sync_result.dart';

/// An observer class to monitor operations within [DatumManager].
///
/// Implement this class and register it via `Datum.addObserver()` (for global
/// observation) or during `Datum.register()` (for entity-specific observation)
/// to receive notifications about key operations.
abstract class DatumObserver<T extends DatumEntity> {
  /// Called at the beginning of a `create` operation.
  void onCreateStart(T item) {}

  /// Called at the end of a successful `create` operation.
  void onCreateEnd(T item) {}

  /// Called at the beginning of an `update` operation.
  void onUpdateStart(T item) {}

  /// Called at the end of a successful `update` operation.
  void onUpdateEnd(T item) {}

  /// Called at the beginning of a `delete` operation.
  void onDeleteStart(String id) {}

  /// Called at the end of a `delete` operation.
  void onDeleteEnd(String id, {required bool success}) {}

  /// Called when a synchronization cycle is about to start.
  void onSyncStart() {}

  /// Called when a synchronization cycle has finished.
  void onSyncEnd(DatumSyncResult result) {}

  /// Called when a conflict is detected between local and remote data.
  void onConflictDetected(T local, T remote, DatumConflictContext context) {}

  /// Called after a conflict has been resolved.
  void onConflictResolved(DatumConflictResolution<T> resolution) {}

  /// Called when a user switch operation is about to start.
  void onUserSwitchStart(
    String? oldUserId,
    String newUserId,
    UserSwitchStrategy strategy,
  ) {}

  /// Called when a user switch operation has finished.
  void onUserSwitchEnd(DatumUserSwitchResult result) {}
}

/// A specialized observer that can handle any entity type.
/// This is used for global observers registered on the main `Datum` instance.
abstract class GlobalDatumObserver extends DatumObserver<DatumEntity> {
  @override
  void onCreateStart(DatumEntity item) {}
  @override
  void onCreateEnd(DatumEntity item) {}
  @override
  void onUpdateStart(DatumEntity item) {}
  @override
  void onUpdateEnd(DatumEntity item) {}
  @override
  void onConflictDetected(
    DatumEntity local,
    DatumEntity remote,
    DatumConflictContext context,
  ) {}
  @override
  void onConflictResolved(DatumConflictResolution<DatumEntity> resolution) {}
}
