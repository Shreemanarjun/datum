# Sync engine audit

What a production sync engine exposes, where Datum stood, what was changed,
and what is still open. Compared against the Rust/C/C++ engines listed under
[Sources](#sources).

## 1. Capability comparison

"Had" = already in Datum. "Added" = added in this pass. "Open" = not available.

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
| Server-requested backoff (`Retry-After`) | Mozilla | Open |
| Sync reason tag | Mozilla | Open |

### Change tracking and upload

| Capability | Others | Datum |
|---|---|---|
| Persistent operation queue, ordered per item | PowerSync, Turso | Had |
| Batching and coalescing | Mozilla, LiteCore, Graft | Had: `remoteSyncBatchSize`. Fixed: per-sync `overrideBatchSize` was ignored |
| Idempotent re-send after a lost ack | PowerSync, LiteCore | Had (create is an upsert; covered by crash/replay conformance tests) |
| Discard a poison write | PowerSync | Had: `discardParkedOperations` |
| A local transaction uploaded as one unit | PowerSync, Realm, sqlite-sync | Open: operations upload per entity |

### Download

| Capability | Others | Datum |
|---|---|---|
| Persisted cursor / watermark | all | Had: `DeltaSyncCapable`, `CursorSyncCapable` |
| Partial sync (scopes, filters) | PowerSync, Realm, LiteCore, Electric | Had: `DatumSyncScope`, `DatumSyncOptions.query` |
| Full resync | LiteCore, sqlite-sync, Realm | Fixed: `forceFullSync` did not force a full pull on delta adapters (see §2) |
| Tombstones with purge | LiteCore | Added: `restore`, `purgeTombstones`; a fresh device no longer stores tombstones of rows it never had |
| Logout wipe | sqlite-sync, PowerSync, Mozilla | Added: `clearUserData(userId)` |
| Checksums per bucket | PowerSync, Graft | Partial: one content hash per user and entity type |
| Sync priorities | PowerSync | Open |
| Server-forced refetch | Electric, Realm | Open |

### Conflicts

| Capability | Others | Datum |
|---|---|---|
| Last write wins | most | Had |
| Custom resolver hook | LiteCore | Had: `DatumConflictResolver`, per-sync override |
| CRDT / vector clocks | cr-sqlite, Automerge, Yrs | Had: `crdt.dart`, `VectorClock` |
| Report without resolving | — | Fixed: `resolveConflicts: false` was ignored |
| Fail-on-conflict save | LiteCore | Open |

### Schema migrations

| Capability | Others | Datum |
|---|---|---|
| Stored version number | Mozilla, Realm, PowerSync | Had |
| All steps in one transaction, rolled back on failure | Mozilla, cr-sqlite | Had |
| Additive auto-migration | Realm | Had: `autoMigrate` |
| **Migration history** (what ran, when, rows, failures) | none verified | Added: `getMigrationHistory()`; persisted by every adapter (SQLite: a `<table>__migrations` table) |
| Newer-store detection | Mozilla | Added as a warning (see §3) |

### Operations

| Capability | Others | Datum |
|---|---|---|
| Storage size, compaction | LiteCore, Realm, Turso | Had: `getStorageSize`. Added: `purgeTombstones` |
| Background isolate | — | Had: `useIsolateSync` |
| Metrics, logging, observers | Turso, Mozilla, PowerSync | Had |
| Attachments / blobs | LiteCore | Open |

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
8. **The `Datum` facade lived inside the engine layer,** so engine, manager
   and models imported each other, and 25 files imported the whole package
   barrel. See §4.

## 3. Still open

- **Local and remote maps share one `diff`.** `toDatumMap(target:)` may use
  different key names per target, but `diff` returns a single map used for
  both the local patch and the remote delta. It works when keys match across
  targets. A clean fix makes the engine compute the two deltas itself.
- **Two places declare the schema version** (adapter constructor and
  `DatumConfig.schemaVersion`). Because many setups version only one, opening
  a store newer than the config logs a warning instead of failing.
- **Last-write-wins trusts device clocks,** and compares `version` before
  time. A device with a fast clock, or one that edited more often, wins.
  Server-assigned time (or a hybrid logical clock) would remove that.
- **Datum's `TimeoutException` shadows `dart:async`'s** for anyone importing
  both.
- **Relation objects live on the entity** and return through a manager, so
  the relational entity model reaches up to the manager layer (the one
  remaining exception to the layer rule).
- Not available: atomic multi-entity upload, sync priorities, server-forced
  refetch, `Retry-After`, fail-on-conflict save, attachments.

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

`test/architecture_test.dart` enforces it. It also forbids importing the
package barrel from inside `lib`, and holds a baseline of known exceptions
that may only shrink (currently the relational entity, above).

Code below the facade reaches sibling managers through
`ManagerLocator` (manager layer), which the facade installs when it starts.

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
