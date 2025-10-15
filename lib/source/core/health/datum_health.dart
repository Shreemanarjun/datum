/// Overall health status levels for the Datum system.
enum DatumHealthStatus {
  /// System is operating normally.
  healthy,

  /// System has non-critical issues that should be monitored.
  warning,

  /// System has critical issues that require immediate attention.
  critical,
}

/// Represents a snapshot of the overall health of the Datum synchronization system.
class DatumHealthCheck {
  /// Creates a health check result.
  const DatumHealthCheck({
    required this.isLocalStorageHealthy,
    required this.isRemoteConnected,
    required this.hasPendingOperations,
    required this.pendingOperationCount,
    required this.hasFailedOperations,
    required this.failedOperationCount,
    this.lastSuccessfulSync,
    this.warnings = const [],
    this.errors = const [],
  });

  /// Whether the local storage adapter is functioning correctly.
  final bool isLocalStorageHealthy;

  /// Whether a connection to the remote data source is available.
  final bool isRemoteConnected;

  /// Whether there are pending operations waiting to be synced.
  final bool hasPendingOperations;

  /// The total number of pending operations.
  final int pendingOperationCount;

  /// Whether there are operations that have failed permanently.
  final bool hasFailedOperations;

  /// The total number of failed operations.
  final int failedOperationCount;

  /// The timestamp of the last successful synchronization.
  final DateTime? lastSuccessfulSync;

  /// A list of non-critical warning messages.
  final List<String> warnings;

  /// A list of critical error messages.
  final List<String> errors;

  /// A computed property indicating if the system is healthy overall.
  bool get isHealthy =>
      isLocalStorageHealthy && !hasFailedOperations && errors.isEmpty;

  /// The current overall health status level.
  DatumHealthStatus get status {
    if (!isHealthy) return DatumHealthStatus.critical;
    if (warnings.isNotEmpty || hasPendingOperations) {
      return DatumHealthStatus.warning;
    }
    return DatumHealthStatus.healthy;
  }
}
