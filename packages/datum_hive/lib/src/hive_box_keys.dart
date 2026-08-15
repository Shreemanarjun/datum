/// Composite box-key codec shared by the Hive adapters.
///
/// Entities are keyed by `(userId, id)` so different users can own rows with
/// the same entity id — matching the `LocalAdapter` contract certified by the
/// conformance kit (and `InMemoryLocalAdapter`'s per-user partitioning).
/// Keying by id alone let one user's write or delete silently destroy another
/// user's row.
///
/// Both parts are percent-escaped (`%` and `:`) so the `::` separator can
/// never be forged by a crafted userId or id.
library;

String _escape(String part) => part.replaceAll('%', '%25').replaceAll(':', '%3A');

String _unescape(String part) => part.replaceAll('%3A', ':').replaceAll('%25', '%');

/// The box key for an entity owned by [userId] with entity id [id].
String hiveBoxKey(String userId, String id) => '${_escape(userId)}::${_escape(id)}';

/// Decodes a composite box key back into `(userId, id)`.
///
/// Returns null for keys that don't use the composite format (legacy rows
/// keyed by bare id before the adapter migrated them).
({String userId, String id})? decodeHiveBoxKey(String key) {
  final separator = key.indexOf('::');
  if (separator < 0) return null;
  return (
    userId: _unescape(key.substring(0, separator)),
    id: _unescape(key.substring(separator + 2)),
  );
}
