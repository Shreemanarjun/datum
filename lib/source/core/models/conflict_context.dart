import 'package:datum/source/core/models/datum_sync_metadata.dart';

/// Types of conflicts detected between local and remote representations.
enum DatumConflictType {
  /// Both local and remote versions were modified independently.
  bothModified,

  /// Entity user ownership changed between versions.
  userMismatch,

  /// One version was deleted while the other was modified.
  deletionConflict,
}

/// Context information describing a synchronization conflict.
class DatumConflictContext {
  /// Creates a conflict context.
  const DatumConflictContext({
    required this.userId,
    required this.entityId,
    required this.type,
    required this.detectedAt,
    this.localMetadata,
    this.remoteMetadata,
  });

  /// User ID associated with the conflict.
  final String userId;

  /// Entity ID involved in the conflict.
  final String entityId;

  /// Type of conflict detected.
  final DatumConflictType type;

  /// Metadata from the local version.
  final DatumSyncMetadata? localMetadata;

  /// Metadata from the remote version.
  final DatumSyncMetadata? remoteMetadata;

  /// Timestamp when the conflict was detected.
  final DateTime detectedAt;
}
