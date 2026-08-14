/// Per-user cache of the order-independent content hash and entity count
/// that back sync-metadata stamping.
///
/// After every sync cycle the engine stamps metadata with a content hash of
/// the full local dataset. Recomputing that is O(n) (a `readAll` plus a
/// SHA-256 per entity) — wasted work for the common auto-sync case where
/// nothing changed between cycles. This cache keeps the last computed
/// `(hash, count)` per user; every local write chokepoint invalidates the
/// user's entry, so a hit is only possible when the store is provably
/// unchanged since the last computation.
///
/// Correctness note: writes that bypass both the manager and the adapter's
/// `changeStream` (out-of-band storage edits) are invisible to the cache —
/// the same writes are already invisible to queueing and reactivity. The
/// cache can be disabled wholesale with
/// `DatumConfig.enableMetadataHashCache: false`.
class MetadataHashCache {
  final Map<String, ({String hash, int count})> _entries = {};

  /// The cached hash/count for [userId], or null when a recompute is needed.
  ({String hash, int count})? peek(String userId) => _entries[userId];

  /// Stores a freshly computed [hash]/[count] for [userId].
  void store(String userId, {required String hash, required int count}) {
    _entries[userId] = (hash: hash, count: count);
  }

  /// Drops [userId]'s entry — call from every local write chokepoint.
  void invalidate(String userId) => _entries.remove(userId);

  /// Drops every entry (bulk operations: migrations, clear, user switches).
  void invalidateAll() => _entries.clear();
}
