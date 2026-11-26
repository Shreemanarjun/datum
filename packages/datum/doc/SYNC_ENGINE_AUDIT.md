# Sync engine audit

What a production sync engine exposes, where Datum stood, what was changed,
and what is still open. Compared against the Rust/C/C++ engines listed under
[Sources](#sources).

## 1. Capability comparison

"Had" = already in Datum. "Added" / "Fixed" = done in this pass. Anything
else says why.

### Sync control

| Capability | Others | Datum |
|---|---|---|
| Sync now, push-only, pull-only | LiteCore, Turso, sqlite-sync | Had: `synchronize`, `SyncDirection` |
| Periodic sync, pause, resume | Realm, LiteCore | Had: `startAutoSync`, `pauseSync`, `resumeSync` |
| Sync soon after a local write | PowerSync (`crudThrottleTime`) | Added: `DatumConfig.syncAfterWriteDelay` |
| Interrupt a running sync | Mozilla, Realm | Added: `cancelSync()` |
| Wait until uploads are done | PowerSync, Realm | Added: `waitUntilSynced(userId, {timeout})` |
| Status and progress streams | PowerSync, Realm, LiteCore | Had: `statusStream`, `onSyncProgress`, `health` |
| Pending-upload count | PowerSync, Turso, Graft | Had: `getPendingCount`. Added: live `watchPendingCount`, `watchPendingOperations` |
| Is this item still pending? | LiteCore (`isDocumentPending`) | Added: `isPending(id, userId:)` |
| Per-item permanent failures | LiteCore, Mozilla, Realm | Had: parked operations, `retryParkedOperations`, `discardParkedOperations` |
| Backoff between retries | Realm, LiteCore, Mozilla | Fixed: the configured backoff was never applied (see §2) |
| Pause on expired login, resume on sign-in | PowerSync, Realm (token refresh) | Added: `AuthErrorPolicy.pauseSync` + `DatumConfig.authState` |
| Server-requested backoff (`Retry-After`) | Mozilla | Added: `NetworkException.retryAfter`; the engine never retries sooner |
| Sync reason tag | Mozilla | Added: `DatumSyncOptions.reason` → `DatumSyncStartedEvent.reason` |

### Change tracking and upload

| Capability | Others | Datum |
|---|---|---|
| Persistent operation queue, ordered per item | PowerSync, Turso | Had |
| Batching and coalescing | Mozilla, LiteCore, Graft | Had: `remoteSyncBatchSize`. Fixed: per-sync `overrideBatchSize` was ignored |
| Idempotent re-send after a lost ack | PowerSync, LiteCore | Had (create is an upsert; covered by crash/replay conformance tests) |
| Discard a poison write | PowerSync | Had: `discardParkedOperations` |
| A local transaction uploaded as one unit | PowerSync, Realm, sqlite-sync | By design: see §3 |

### Download

| Capability | Others | Datum |
|---|---|---|
| Persisted cursor / watermark | all | Had: `DeltaSyncCapable`, `CursorSyncCapable` |
| Partial sync (scopes, filters) | PowerSync, Realm, LiteCore, Electric | Had: `DatumSyncScope`, `DatumSyncOptions.query` |
| Full resync | LiteCore, sqlite-sync, Realm | Fixed: `forceFullSync` did not force a full pull on delta adapters (see §2) |
| Tombstones with purge | LiteCore | Added: `restore`, `purgeTombstones`; a fresh device no longer stores tombstones of rows it never had |
| Logout wipe | sqlite-sync, PowerSync, Mozilla | Added: `clearUserData(userId)` |
| Checksums per bucket | PowerSync, Graft | Partial: one content hash per user and entity type |
| Sync priorities | PowerSync | Had: managers sync in registration order (now tested) |
| Server-forced refetch | Electric, Realm | Added: `ResyncRequiredException` → the engine reads everything again |

### Conflicts

| Capability | Others | Datum |
|---|---|---|
| Last write wins | most | Had |
| Custom resolver hook | LiteCore | Had: `DatumConflictResolver`, per-sync override |
| CRDT / vector clocks | cr-sqlite, Automerge, Yrs | Had: `crdt.dart`, `VectorClock` |
| Report without resolving | — | Fixed: `resolveConflicts: false` was ignored |
| Fail-on-conflict save | LiteCore | Added: `push(expectedVersion:)` throws `ConflictException` |
| Clock-free conflict policy | Turso (last push wins) | Had: `RemotePriorityResolver` (now tested under clock skew, see §3) |

### Schema migrations

| Capability | Others | Datum |
|---|---|---|
| Stored version number | Mozilla, Realm, PowerSync | Had |
| All steps in one transaction, rolled back on failure | Mozilla, cr-sqlite | Had |
| Additive auto-migration | Realm | Had: `autoMigrate` |
| **Migration history** (what ran, when, rows, failures) | none verified | Added: `getMigrationHistory()`; persisted by every adapter (SQLite: a `<table>__migrations` table) |
| Newer-store detection | Mozilla | Added: refused when the app versions its schema, warned otherwise |

### Operations

| Capability | Others | Datum |
|---|---|---|
| Storage size, compaction | LiteCore, Realm, Turso | Had: `getStorageSize`. Added: `purgeTombstones` |
| Background isolate | — | Had: `useIsolateSync` |
| Metrics, logging, observers | Turso, Mozilla, PowerSync | Had |
| Attachments / blobs | LiteCore | Not a goal: see §3 |

## 2. Conventions that were wrong (fixed)

1. **Options that were declared but never read.** `backoffStrategy.getDelay`
   was never called, so no backoff existed; `DatumSyncOptions.includeDeletes`,
   `resolveConflicts` and `overrideBatchSize` were copied around and ignored.
   All four are now honored and covered by tests. A retryable failure is
   retried by a scheduled sync after the backoff delay.
2. **`forceFullSync` did not mean a full sync.** It only skipped the "nothing
   changed" shortcut; a delta-capable adapter still pulled the delta. It now
   also reads everything.
3. **Hard-coded map keys.** Adapters and the manager assumed camelCase keys
   (`userId`, `isDeleted`, `modifiedAt`) while generated entities write
   snake_case. Consequences: Hive hid every generated entity, SQLite rejected
   them, and `delete(softDelete)` left the row un-deleted. Owner and tombstone
   handling now go through the entity, and a key-naming conformance suite
   (`runKeyNamingConformanceTests`) covers every adapter.
4. **`diff` skipped `isDeleted` in generated code.** Pushing
   `copyWith(isDeleted: true)` was a silent no-op, which is why undo, redo and
   clear did nothing in the paint screen. Generated diffs now include it, and
   `@DatumField(diff: false/true)` lets a field opt out or in.
5. **`diff` mixed local and remote value formats.** The default `diff`
   compared local maps and sent epoch-ms timestamps to the server. It now
   diffs remote maps; the local patch uses local values.
6. **Timestamps compared with `==`** (false across time zones) and sent
   without an offset. Fixed earlier in this branch.
7. **One sync-metadata row per user shared by all entity types** in the
   example's Supabase schema; each manager overwrote the others.
8. **Cold start re-read everything.** The default (`adaptive`) cold-start
   strategy forced a full sync on every app start. It now runs a normal
   cycle; only the `fullSync` strategy re-reads the remote.
9. **Sync options were copied field by field in three places,** so a new
   option had to be added three times (and the facade copy had already
   drifted). `DatumSyncOptions.retype` replaces them.
10. **The `Datum` facade lived inside the engine layer,** so engine, manager
   and models imported each other, and 25 files imported the whole package
   barrel. See §4.

## 3. Earlier open items: how each was closed

- **One `diff` for both the local patch and the remote delta.** Fixed. The
  entity's `diff` goes upstream; the local store is patched with the diff of
  the local maps, so key names and formats may differ per target. Fields the
  remote also has but the entity did not report (`createdAt`, or a generated
  field marked `@DatumField(diff: false)`) are left alone on both sides, so
  the local row always equals what the remote holds.
- **Two places declare the schema version.** A store newer than the app is
  now refused when the app versions its schema through Datum
  (`schemaVersion > 0` or any migration); an app that never versioned it only
  gets the warning.
- **Datum's `TimeoutException` shadowed `dart:async`'s.** Renamed to
  `DatumTimeoutException` (breaking). A sync timeout now throws it.
- **Relation objects reached up to the manager layer.** Fixed with a small
  port in the model layer (`RelatedSource`, implemented by `DatumManager`).
  The dependency rule now holds with no exceptions.
- **Last-write-wins and device clocks.** Kept, and documented, because the
  version check already orders edits made one after the other: an edit made
  after seeing another always has the higher version and wins whatever the
  clocks say (the same rule as Couchbase Lite's revision generation). Clocks
  only decide edits made at the same time from the same version. Apps that
  must not depend on device clocks at all use `RemotePriorityResolver`: with
  the default direction the last push wins, with `pullThenPush` the first
  push wins. Both are covered by a conformance test that gives the losing
  device a clock 10 minutes fast. `LocalPriorityResolver` on every device
  never converges and is only for a single authoritative device.
- **Server-requested backoff, forced refetch, fail-on-conflict save, sync
  reason, sync priorities.** Added or confirmed; see §1.

Not goals, with the reason:

- **One atomic upload across entity types.** Each entity type has its own
  remote adapter and queue, so the engine cannot offer it. Within one type,
  consecutive creates, updates or deletes already go out as one bulk call
  (`createAll` / `updateAll` / `deleteAll`), which is atomic when the backend
  makes that call atomic (a Supabase upsert of a list is one statement). Data
  that must change together belongs in one entity, or behind one server-side
  function.
- **Attachments.** Files belong in object storage. Sync the reference (URL,
  digest) as a normal field.
- **Device-only fields.** A field must exist in both maps. A value that
  should never leave the device belongs in the app's own storage: a pulled
  remote update replaces the whole local row.

Still worth doing later: checksums per sync scope (today: one content hash
per user and entity type).

## 4. Layers

`lib/source` follows the dependency rule: a file may import its own layer and
the ones above it in this list, never one below.

| Rank | Layer | Directories |
|---|---|---|
| 0 | utils | `utils` |
| 1 | domain | `core/models`, `errors`, `query`, `schema`, `resolver`, `health`, `events`, `middleware`, `utils` |
| 2 | adapter contracts | `adapter` |
| 3 | services | `core/migration`, `core/sync`, `core/persistence` |
| 4 | config | `config` |
| 5 | sync engine | `core/engine` |
| 6 | manager | `core/manager` |
| 7 | facade | `core/facade` (`Datum`) |

`test/architecture_test.dart` enforces it, and forbids importing the package
barrel from inside `lib`. There are no exceptions.

Code below the facade reaches sibling managers through `ManagerLocator`
(manager layer) and relation objects through `RelatedSources` (model
layer); the facade installs both when it starts.

## Sources

- https://docs.powersync.com/architecture/client-architecture
- https://docs.powersync.com/architecture/powersync-protocol
- https://docs.powersync.com/handling-writes/handling-write-validation-errors
- https://pub.dev/documentation/powersync/latest/powersync/PowerSyncDatabase-class.html
- https://raw.githubusercontent.com/powersync-ja/powersync-sqlite-core/main/crates/core/src/migrations.rs
- https://raw.githubusercontent.com/realm/realm-core/master/src/realm/sync/config.hpp
- https://raw.githubusercontent.com/realm/realm-core/master/src/realm/object-store/sync/sync_session.hpp
- https://raw.githubusercontent.com/realm/realm-core/master/src/realm/sync/noinst/client_reset.hpp
- https://github.com/couchbase/couchbase-lite-core/wiki/Replication-Protocol
- https://raw.githubusercontent.com/couchbase/couchbase-lite-core/master/C/include/c4Replicator.h
- https://docs.couchbase.com/couchbase-lite/current/c/conflict.html
- https://github.com/vlcn-io/cr-sqlite
- https://vlcn.io/docs/cr-sqlite/migrations
- https://raw.githubusercontent.com/sqliteai/sqlite-sync/main/API.md
- https://mozilla.github.io/application-services/book/design/sync-manager.html
- https://raw.githubusercontent.com/mozilla/application-services/main/components/support/sql/src/open_database.rs
- https://docs.turso.tech/sync/usage
- https://graft.rs/docs/sqlite/pragmas/
- https://electric.ax/docs/api/http
- https://docs.rs/automerge/latest/automerge/sync/index.html
- https://docs.rs/yrs/latest/yrs/
