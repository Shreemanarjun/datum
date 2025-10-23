import 'package:datum/source/core/models/conflict_context.dart';
import 'package:datum/source/core/models/datum_entity.dart';
import 'package:datum/source/core/models/datum_sync_metadata.dart';

/// Detects conflicts between local and remote versions of an entity.
class DatumConflictDetector<T extends DatumEntityBase> {
  /// Detects conflicts between local and remote items.
  ///
  /// Returns a [DatumConflictContext] if a conflict is detected, otherwise null.
  DatumConflictContext? detect({
    required T? localItem,
    required T? remoteItem,
    required String userId,
    DatumSyncMetadata? localMetadata,
    DatumSyncMetadata? remoteMetadata,
  }) {
    // Case 3: User ID mismatch. This indicates a data ownership problem.
    if (remoteItem != null && remoteItem.userId != userId) {
      return DatumConflictContext(
        userId: userId,
        entityId: remoteItem.id,
        type: DatumConflictType.userMismatch,
        localMetadata: localMetadata,
        remoteMetadata: remoteMetadata,
        detectedAt: DateTime.now(),
      );
    }

    // Case 1: Both are null, no conflict.
    if (localItem == null && remoteItem == null) {
      return null;
    }

    // Case 2: One exists, the other doesn't. This is a normal sync operation, not a conflict.
    if (localItem == null || remoteItem == null) {
      return null;
    }

    // Case 4: Deletion conflict. One side deleted the item, the other modified it.
    if (localItem.isDeleted != remoteItem.isDeleted) {
      return DatumConflictContext(
        userId: userId,
        entityId: localItem.id,
        type: DatumConflictType.deletionConflict,
        localMetadata: localMetadata,
        remoteMetadata: remoteMetadata,
        detectedAt: DateTime.now(),
      );
    }

    // Case 5: Both modified. If versions differ, it's a clear sign of independent modification.
    if (localItem.version != remoteItem.version) {
      return DatumConflictContext(
        userId: userId,
        entityId: localItem.id,
        type: DatumConflictType.bothModified,
        localMetadata: localMetadata,
        remoteMetadata: remoteMetadata,
        detectedAt: DateTime.now(),
      );
    }

    return null;
  }
}
