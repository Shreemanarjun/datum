---
title: Incremental Sync (Delta & Cursor Pulls)
description: Pull only what changed instead of the full dataset — the biggest scalability lever for large stores.
---

By default, a sync cycle that has work to do pulls the **full remote dataset**
and reconciles it locally. That is correct and simple — and wasteful once a
user has thousands of rows. Incremental sync lets your remote adapter answer
*"what changed since last time?"* so each pull transfers only the delta.

Datum supports two incremental strategies. Both are **opt-in by the adapter**
(mix in a capability) and **on by default** once the adapter is capable:

| Strategy | Mixin | Watermark | Best for |
|---|---|---|---|
| Timestamp delta | `DeltaSyncCapable` | `DateTime` since-value | REST/SQL backends with a server-maintained `updated_at` column |
| Cursor feed | `CursorSyncCapable` | Opaque `String` cursor | Changes-feed backends: Firestore tokens, CouchDB sequences, DynamoDB streams, monotonic counters |

When an adapter advertises **both**, the cursor path wins — it is immune to
clock skew entirely.

## 1. Timestamp delta: implement `readSince`

Add the mixin to your remote adapter and implement one method:

```dart
class DeltaRestAdapter extends RemoteAdapter<Task> with DeltaSyncCapable<Task> {
  DeltaRestAdapter(this._api);
  final RestClient _api;

  @override
  String get name => 'DeltaRestAdapter';

  @override
  Future<List<Task>> readSince(DateTime since, {String? userId, DatumSyncScope? scope}) async {
    // e.g. GET /tasks?updated_since=<since>&user=<userId>
    final rows = await _api.fetchTasksSince(since, userId: userId);
    final items = rows.map(Task.fromMap).toList();
    return scope == null ? items : DatumQueryMatcher.apply(items, scope.query);
  }

  // ... the regular RemoteAdapter surface (readAll, create, update, ...)
  @override
  Future<List<Task>> readAll({String? userId, DatumSyncScope? scope}) async {
    final items = (await _api.fetchAllTasks(userId: userId)).map(Task.fromMap).toList();
    return scope == null ? items : DatumQueryMatcher.apply(items, scope.query);
  }

  @override
  Future<Task?> read(String id, {String? userId}) async => null;
  @override
  Future<List<Task>> query(DatumQuery query, {String? userId}) async => DatumQueryMatcher.apply(await readAll(userId: userId), query);
  @override
  Future<void> create(Task entity) async => _api.upsertTask(entity.toDatumMap(target: MapTarget.remote));
  @override
  Future<void> update(Task entity) async => _api.upsertTask(entity.toDatumMap(target: MapTarget.remote));
  @override
  Future<Task> patch({required String id, required Map<String, dynamic> delta, String? userId}) async => throw UnimplementedError();
  @override
  Future<bool> delete(String id, {String? userId}) async => _api.deleteTask(id);
  @override
  Future<DatumSyncMetadata?> getSyncMetadata(String userId) async => null;
  @override
  Future<void> updateSyncMetadata(DatumSyncMetadata metadata, String userId) async {}
  @override
  Future<bool> isConnected() async => true;
  @override
  Future<void> initialize() async {}
  @override
  Future<void> dispose() async {}
  @override
  Stream<DatumChangeDetail<Task>>? get changeStream => null;
}

/// Stand-in for your HTTP client so this page compiles end to end.
class RestClient {
  Future<List<Map<String, dynamic>>> fetchTasksSince(DateTime since, {String? userId}) async => [];
  Future<List<Map<String, dynamic>>> fetchAllTasks({String? userId}) async => [];
  Future<void> upsertTask(Map<String, dynamic> row) async {}
  Future<bool> deleteTask(String id) async => true;
}
```

That's it. The engine now:

- pulls **full** on a user's first sync (no watermark yet),
- pulls **only changed rows** on every later cycle, passing the last sync
  watermark minus a clock-skew overlap,
- still pulls full for cycles that need the complete remote id set
  (`detectRemoteDeletions: true`).

Re-delivered rows inside the overlap window are dropped by the engine's
strictly-newer check, so the overlap is idempotent.

### ⚠️ Compare against a server-set column

Query a **server-maintained** received-at column (e.g. a Postgres trigger
setting `server_updated_at = now()`), *not* the entity's client-set
`modifiedAt`. A device that reconnects after a week pushes rows whose
`modifiedAt` is a week old — older than every other device's watermark — so a
`modifiedAt` comparison silently misses them. A server received-at is always
newer than any previously issued watermark.

### Tuning the overlap

```dart
final tuned = DatumConfig<Task>(
  // Widen for badly skewed client clocks; the overlap is idempotent.
  deltaSyncOverlap: Duration(minutes: 15),
  // Escape hatch: force full pulls even for capable adapters.
  enableDeltaSync: false,
);
```

## 2. Cursor feed: implement `readChanges`

If your backend hands out change tokens instead of timestamps — or you can
keep a monotonically increasing change counter — use the cursor form. A
`null` cursor means *from the beginning*, so even first syncs ride the feed:

```dart
class FeedAdapter extends RemoteAdapter<Task> with CursorSyncCapable<Task> {
  FeedAdapter(this._api);
  final FeedClient _api;

  @override
  String get name => 'FeedAdapter';

  @override
  Future<CursorPage<Task>> readChanges(String? cursor, {String? userId, DatumSyncScope? scope}) async {
    // e.g. GET /changes?cursor=<cursor>  ->  {items: [...], nextCursor: '...'}
    final page = await _api.changes(cursor, userId: userId);
    var items = (page.rows).map(Task.fromMap).toList();
    if (scope != null) items = DatumQueryMatcher.apply(items, scope.query);
    return (items: items, nextCursor: page.nextCursor);
  }

  // ... regular RemoteAdapter surface elided; see the DeltaRestAdapter
  // example above for the full shape.
  @override
  Future<List<Task>> readAll({String? userId, DatumSyncScope? scope}) async => (await readChanges(null, userId: userId, scope: scope)).items;
  @override
  Future<Task?> read(String id, {String? userId}) async => null;
  @override
  Future<List<Task>> query(DatumQuery query, {String? userId}) async => DatumQueryMatcher.apply(await readAll(userId: userId), query);
  @override
  Future<void> create(Task entity) async {}
  @override
  Future<void> update(Task entity) async {}
  @override
  Future<Task> patch({required String id, required Map<String, dynamic> delta, String? userId}) async => throw UnimplementedError();
  @override
  Future<bool> delete(String id, {String? userId}) async => true;
  @override
  Future<DatumSyncMetadata?> getSyncMetadata(String userId) async => null;
  @override
  Future<void> updateSyncMetadata(DatumSyncMetadata metadata, String userId) async {}
  @override
  Future<bool> isConnected() async => true;
  @override
  Future<void> initialize() async {}
  @override
  Future<void> dispose() async {}
  @override
  Stream<DatumChangeDetail<Task>>? get changeStream => null;
}

/// Stand-in feed client so this page compiles end to end.
class FeedClient {
  Future<({List<Map<String, dynamic>> rows, String nextCursor})> changes(String? cursor, {String? userId}) async => (rows: <Map<String, dynamic>>[], nextCursor: '0');
}
```

The returned `nextCursor` is persisted **per device** in the local sync
metadata and handed back on the next cycle. Datum deliberately strips the
cursor from the remote metadata beacon: a foreign device adopting another
device's cursor would silently skip changes it has never seen.

## 3. Deletions under incremental sync

An incremental pull only sees rows the backend *returns*. That means:

- **Soft deletes propagate naturally** — flipping `isDeleted` bumps the
  server column / feed sequence, so tombstones ride the delta. This is
  Datum's recommended model (`DeleteBehavior.softDelete`).
- **Hard deletions are invisible** — a row that vanished server-side never
  appears in a delta. Either keep soft deletes, emit tombstones into your
  change feed, or enable `detectRemoteDeletions: true` and accept full-scan
  pull cycles.

## 4. Verifying your adapter

The [`datum_test`](/guides/testing) conformance kit checks the contracts for
you — `readSince`'s inclusive watermark, and the full sync-stack matrix over
your adapter pair:

```dart no-verify
runRemoteAdapterConformanceTests(
  name: 'DeltaRestAdapter',
  create: () async => DeltaRestAdapter(RestClient()),
);
```

## Watching it work

Enable logging and look for the pull lines:

```
[Datum INFO]: Delta pull for user u1: entities modified since 2026-08-14 10:02:11.
[Datum INFO]: Cursor pull for user u1 (cursor: 4182).
```

A full pull instead logs `Pulling remote changes for user u1...` — expected
on first syncs and `detectRemoteDeletions` cycles.
