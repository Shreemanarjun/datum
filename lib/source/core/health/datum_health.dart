import 'package:equatable/equatable.dart';

/// Represents the operational health of a sync manager.
class DatumHealth extends Equatable {
  /// The overall status of the manager.
  final DatumSyncHealth status;

  /// The health status of the local data adapter.
  final AdapterHealthStatus localAdapterStatus;

  /// The health status of the remote data adapter.
  final AdapterHealthStatus remoteAdapterStatus;

  const DatumHealth({
    this.status = DatumSyncHealth.healthy,
    this.localAdapterStatus = AdapterHealthStatus.healthy,
    this.remoteAdapterStatus = AdapterHealthStatus.healthy,
  });

  @override
  List<Object?> get props => [status, localAdapterStatus, remoteAdapterStatus];
}

/// Describes the overall health of a synchronization process.
enum DatumSyncHealth {
  healthy,
  syncing,
  pending,
  degraded,
  offline,
  error,
}

/// Describes the health of an individual adapter.
enum AdapterHealthStatus {
  /// The adapter is functioning correctly.
  healthy,

  /// The adapter is unreachable or has failed.
  unhealthy,
}
