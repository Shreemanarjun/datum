/// Strategy for choosing between the local and remote data sources when
/// fetching data via [DatumManager.fetch] / [DatumManager.fetchById].
///
/// This removes the repetitive "try local, then fall back to remote" boilerplate
/// that offline-first apps otherwise hand-write. See issue #17.
enum DataFetchStrategy {
  /// Query the local adapter only (never touches the network).
  localOnly,

  /// Query the remote adapter only.
  remoteOnly,

  /// Try the local adapter first; if it returns no results, fetch from the
  /// remote adapter. Optionally persist the remote results locally.
  ///
  /// Best for offline-first reads where cached data is preferred.
  localFirst,

  /// Try the remote adapter first; if it fails (e.g. offline / error), fall
  /// back to the local adapter.
  ///
  /// Best for "fresh when possible, cached when not" reads.
  remoteFirst,
}
