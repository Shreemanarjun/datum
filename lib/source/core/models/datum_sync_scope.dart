import 'package:datum/source/core/query/datum_query.dart';

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
  /// A query used to filter the data fetched from the remote source.
  /// The interpretation of this query is up to the `RemoteAdapter` implementation.
  final DatumQuery query;

  /// Creates a [DatumSyncScope].
  ///
  /// The [query] is passed to the remote adapter's `readAll` method for
  /// filtering pulled data.
  const DatumSyncScope({
    this.query = const DatumQuery(),
  });

  /// A scope that applies a query to a pull operation.
  ///
  /// Example:
  /// ```dart
  /// DatumSyncScope(query: DatumQuery(filters: [Filter('isActive', isEqualTo: true)]))
  /// ```
}
