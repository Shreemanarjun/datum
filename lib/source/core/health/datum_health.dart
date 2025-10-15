import 'package:flutter/foundation.dart';

/// Represents the specific health status of a synchronization process.
enum DatumSyncHealth {
  /// The manager is operating normally with no issues.
  healthy,

  /// A sync cycle is currently in progress.
  syncing,

  /// There are local changes waiting to be pushed to the remote.
  pending,

  /// The manager is experiencing non-critical issues, like network flakiness.
  degraded,

  /// The manager cannot connect to the remote data source.
  offline,

  /// The manager has encountered critical errors and cannot sync.
  error,
}

/// An immutable snapshot of the health of a sync manager.
@immutable
class DatumHealth {
  /// The overall health status.
  final DatumSyncHealth status;

  const DatumHealth({this.status = DatumSyncHealth.healthy});
}
