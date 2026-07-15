# Datum API Guide

A user-facing reference for the current API surface — useful for aligning the
docs site with the shipped features. Covers querying, relations, results/errors,
and configuration added through v1.1.0.

## Querying

### One-time reads

```dart
final manager = Datum.manager<Task>();

await manager.read('id', userId: userId);            // single (local)
await manager.readAll(userId: userId);               // all (local)
await manager.query(myQuery, userId: userId);        // source defaults to local
await manager.query(myQuery, source: DataSource.remote, userId: userId);

await manager.exists('id', userId: userId);          // bool convenience
await manager.count(userId: userId);                 // count all
await manager.count(query: myQuery, userId: userId); // count matches
```

### Fetch strategies (offline-first fallback)

```dart
await manager.fetch(myQuery, strategy: DataFetchStrategy.localFirst,  userId: userId);
await manager.fetch(myQuery, strategy: DataFetchStrategy.remoteFirst, userId: userId,
    persistRemoteResults: true); // cache remote results locally
await manager.fetchById('id', strategy: DataFetchStrategy.localFirst, userId: userId);
```

`localOnly` · `remoteOnly` · `localFirst` (local, then remote if empty) ·
`remoteFirst` (remote, then local on error).

### Type-safe query fields

**Generated entities** get a `<Entity>Query` extension with per-field methods
(`whereTitle`, `orderByPriority`, `withPosts`) plus type conversion.

**Hand-written entities** can declare field descriptors manually and use
`whereField` / `orderByField` for the same compile-time safety:

```dart
abstract class TaskFields {
  static const title    = DatumQueryField<Task, String>('title');
  static const priority = DatumQueryField<Task, int>('priority');
}

final query = (DatumQueryBuilder<Task>()
      ..whereField(TaskFields.priority, isGreaterThanOrEqualTo: 2) // int-checked
      ..whereField(TaskFields.title, contains: 'urgent')
      ..orderByField(TaskFields.priority, descending: true))
    .build();

// Descriptors also build Filters for composite or()/and():
builder.or([TaskFields.priority.greaterThan(4), TaskFields.title.equalTo('urgent')]);
```

### Raw queries (projection / aggregation, no hydration)

Adapters that mix in `RawQueryCapable` support `rawQuery`:

```dart
final rows = await manager.rawQuery(
  const DatumRawQuery(sql: 'SELECT id, name FROM tasks WHERE priority > ?', args: [2]),
  source: DataSource.local,
);
final count = await manager.rawQuery(const DatumRawQuery(count: true), source: DataSource.local);
```

## Relations

### Eager loading (`withRelated`)

All four relation kinds (`BelongsTo`, `HasMany`, `HasOne`, `ManyToMany`) load
via `withRelated`, including **nested** dot-paths:

```dart
final blog = await blogs.read('b1', userId: userId, withRelated: ['posts.author', 'profile']);

// Reactive, too:
blogs.watchAll(userId: userId, withRelated: ['posts']).listen(...);
```

### Reading loaded relations (typed accessors)

```dart
final posts  = blog.relatedList<Post>('posts');   // List<Post>?
final author = post.relatedOne<User>('author');   // User?
```

### Hand-written relational entities

Relations must be memoized (so eager-loaded values persist). Use the mixin:

```dart
class Blog extends RelationalDatumEntity with MemoizedRelations {
  @override
  Map<String, Relation> buildRelations() => {'posts': HasMany<Post>(this, 'blogId')};
}
```

### Preserving relations across updates

```dart
final updated = blog.copyWith(name: 'New')..preserveRelationsFrom(blog); // keeps loaded relations
```

### Instance-free relation schema (for adapters)

```dart
final target = DatumRelationSchema.descriptor(Blog, 'posts')!.targetType; // Post
```

## Collaborative editing (realtime multi-device)

`RgaText` (built on the `RgaList<T>` sequence CRDT) gives editors convergent
concurrent text editing:

```dart
class CollabNote extends DatumEntity {
  final RgaText body;                       // serialized via body.toMap()
  @override
  CollabNote merge(covariant DatumEntityInterface other) => CollabNote(
        body: body.merge((other as CollabNote).body),   // both edits survive
        vectorClock: vectorClock!.merge(other.vectorClock!),
        ...);
}

DatumManager<CollabNote>(
  deviceId: myDeviceId,                     // auto-increments vector clocks
  datumConfig: const DatumConfig(defaultConflictResolver: CRDTResolver()),
  ...);
```

- **Vector clocks are required** — they let the engine detect that two
  same-version copies are *concurrent* and route them into the CRDT merge.
- Contiguous runs (`RgaText.insert`) never interleave with concurrent typing.
- `characterIdAt`/`indexOfCharacter` are stable anchors for remote cursors.
- Resolved merge winners are pushed automatically, so all devices and the
  backend converge. Full walkthrough:
  `test/integration/collaborative_editor_test.dart`.

## Results & errors

### Result-returning (`tryX`) API — no try/catch

```dart
final result = await manager.tryPush(item: task, userId: userId);
switch (result) {
  case Success(value: final saved): print(saved);
  case Failure(value: final DatumError e): switch (e) {
    case NetworkError(isRetryable: final r): ...
    case NotFoundError(): ...
    case ValidationError() || ConflictError() || StorageError() || UnknownError(): ...
  }
}
```

Available: `tryRead`, `tryReadAll`, `tryPush`, `tryQuery`, `tryDelete`,
`trySaveMany`, `trySynchronize`, `trySwitchUser`, `tryCascadeDelete`.

### `Datum.initialize`

```dart
final either = await Datum.initialize(...); // DatumEither<DatumError, Datum>
if (either.isFailure()) throw either.failure!;   // DatumError is an Exception
final datum = either.success!;
```

### Readable logging

```dart
print((await manager.synchronize(userId)).describe());  // multi-line summary
print((await manager.checkHealth()).describe());
```

## Configuration

`DatumConfig` (and `DatumConfigPresets.custom(...)`) flags of note:

| Flag | Default | Purpose |
|------|---------|---------|
| `enableQueryCache` | `false` | Cache local `query()` results (off — avoids stale/reactive issues). |
| `detectRemoteDeletions` | `false` | Treat local-only entities as remote deletions on a full pull (resolver-gated). |
| `excludedSyncUserIds` | `{}` | Keep local-only/system users out of auto-discovery and sync. |
| `defaultConflictResolver` | LWW | Global resolver; propagated to every entity manager. |

Reactive `watch*` methods return **non-null** streams (an empty stream when the
adapter isn't `WatchableAdapter`), so no null-checks are needed at call sites.
