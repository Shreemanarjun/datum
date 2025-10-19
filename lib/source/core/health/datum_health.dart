// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

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
class DatumHealth extends Equatable {
  /// The overall health status.
  final DatumSyncHealth status;

  const DatumHealth({this.status = DatumSyncHealth.healthy});

  @override
  bool get stringify => true;

  @override
  List<Object> get props => [status];
}
