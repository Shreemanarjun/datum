/// Defines the scope of a synchronization operation triggered after a local change.
enum DatumSyncTrigger {
  /// Syncs only the specific entity that was just modified.
  ///
  /// This is more efficient if you want to immediately push a single change
  /// without processing the entire queue of pending operations for the user.
  entity,

  /// Syncs all pending operations for the user.
  ///
  /// This is the default behavior and ensures all local changes are pushed.
  user,
}

/// Defines a scope for a synchronization operation, allowing for partial syncs.
class DatumSyncScope {
  /// A map of key-value pairs used to filter the data fetched from the remote.
  /// The interpretation of these filters is up to the `RemoteAdapter` implementation.
  final Map<String, dynamic> filters;

  /// Defines the scope of a synchronization operation triggered after a
  /// local change.
  final DatumSyncTrigger trigger;

  /// Creates a [DatumSyncScope].
  ///
  /// [filters] are passed to the remote adapter's `readAll` method for
  /// filtering pulled data.
  /// [trigger] defines the scope of a sync triggered after a local change.
  const DatumSyncScope({
    this.filters = const {},
    this.trigger = DatumSyncTrigger.user,
  });

  /// A scope that applies filters to a pull operation.
  ///
  /// Example: `DatumSyncScope.filter({'minModifiedDate': '2023-01-01T00:00:00Z'})`
  const DatumSyncScope.filter(this.filters) : trigger = DatumSyncTrigger.user;

  /// A scope that defines the trigger behavior for a sync after a local change.
  const DatumSyncScope.trigger(this.trigger) : filters = const {};
}
