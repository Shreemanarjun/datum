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
| Report changes received live (no sync cycle) | PowerSync (`lastSyncedAt`), Electric (`up-to-date`) | Added: `onLiveChangesApplied` (`LiveChangesAppliedEvent`: count, apply time, when the edit was made) |
| Catch up after reconnect | Realm, PowerSync, LiteCore (continuous) | Fixed: only users with pending uploads were synced; now every auto-synced user is |

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
| Partial sync (scopes, filters) | PowerSync, Realm, LiteCore, Electric | Had: `DatumSyncScope`, `DatumSyncOptions.query`. Fixed: one pull position per device made a second scope miss rows (see §2) |
| Full resync | LiteCore, sqlite-sync, Realm | Fixed: `forceFullSync` did not force a full pull on delta adapters (see §2) |
| Tombstones with purge | LiteCore | Added: `restore`, `purgeTombstones`; a fresh device no longer stores tombstones of rows it never had |
| Logout wipe | sqlite-sync, PowerSync, Mozilla | Added: `clearUserData(userId)` |
| Checksums per bucket | PowerSync, Graft | Added: the "nothing changed" check and the pull position are kept per sync scope |
| Sync priorities | PowerSync | Had: managers sync in registration order (now tested) |
| Server-forced refetch | Electric, Realm | Added: `ResyncRequiredException` → the engine reads everything again |

### Conflicts

| Capability | Others | Datum |
|---|---|---|
| Last write wins | most | Had |
| Custom resolver hook | LiteCore | Had: `DatumConflictResolver`, per-sync override |
| CRDT / vector clocks | cr-sqlite, Automerge, Yrs | Had: `crdt.dart`, `VectorClock` |
| Report without resolving | — | Fixed: `resolveConflicts: false` was ignored |
| No local change → take the server's row | Mozilla, PowerSync | Fixed: every newer remote row went through the resolver (see §2) |
| Base version of an unsynced edit | Mozilla (mirror), Couchbase Lite (parent revision) | Added: `DatumSyncOperation.baseVersion`; an unchanged remote row is not a conflict |
| Look before uploading | Mozilla (download, reconcile, upload) | Changed: the default direction is `pullThenPush` |
| Exact concurrency on every device | cr-sqlite, Automerge, Couchbase Lite | Had: vector clocks (now covered end to end for edits both sides already uploaded) |
| Refuse a stale upload (compare-and-set) | Couchbase Lite (409 on a non-descendant revision), Mozilla (`X-If-Unmodified-Since`), PowerSync (backend decides) | Added: `GuardedWriteCapable`; the example's Supabase adapter implements it |
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
11. **Timestamps compared as text, or finer than the store keeps them.** The
   echo filter keyed a change by `modifiedAt.toIso8601String()`, which
   differs between a local-time and a UTC value of the same instant, so the
   feed's echo of every local write was saved again. The conflict detector
   compared to the microsecond while local stores keep milliseconds, so a
   row updated through a delta (which carries microseconds to the server)
   was a "conflict" on every later pull, resolved and rewritten each time.
   Both now compare instants in milliseconds; content still decides when two
   edits share a millisecond.
12. **The echo of a local write was recorded after the write.** Adapters emit
   the change before the write returns, so the echo was processed as an
   outside change (a read, a diff and a bogus "bytes pulled" event per
   write). It is recorded first now.
13. **"Nothing changed" was decided from a metadata row for every remote.**
   The row is written by the device that pushes; a device that only
   receives could skip the pull that would have brought a missed change. An
   incremental pull costs one small request, so delta and cursor remotes
   always ask; the metadata check remains for remotes that re-read
   everything.
14. **Live changes were invisible to the app.** Changes applied from a
   realtime feed fired no sync event, so a "last sync" display only moved on
   the device that made the edit. `LiveChangesAppliedEvent` reports them.
15. **Every newer remote row was a conflict.** Without vector clocks, any
   pulled row whose version differed from the local one went to the conflict
   resolver, even when the device had not edited it. The default resolver
   took the newer row anyway, but it was counted as a conflict, and
   `LocalPriorityResolver` or a prompting resolver rejected or held ordinary
   edits from other devices. A newer remote row now replaces a local row
   that has no unsynced edit (the rule Mozilla's sync and PowerSync use: no
   local change, take the server's).
16. **An unsynced edit conflicted with its own starting point.** A pull that
   returned the remote row as it was before the local edit (a pull-first
   sync, or the pull after an upload that failed) saw two different
   versions and called it a conflict. `RemotePriorityResolver` then threw
   the edit away, and a merge resolver merged the edit with its ancestor.
   Each queued operation now records the version its edit started from
   (`baseVersion`); a remote row still at that version is left alone.
17. **Uploading before looking.** With push first as the default, a device
   replaced whatever another device had uploaded meanwhile, and no resolver
   was asked. The default is now `pullThenPush`: an unsynced edit meets the
   other device's upload on the device that still holds it, before anything
   is overwritten. `pushThenPull` remains for apps that want the last
   upload to win.
18. **One pull position per device, whatever the scope.** After syncing one
   `DatumSyncScope`, a sync of another scope was skipped as "nothing
   changed" (full-read remotes) or started from the first scope's cursor or
   watermark (incremental remotes), so the rows the first scope had filtered
   out were never downloaded. The position and the unchanged-check are now
   kept per scope.
19. **Live changes bypassed every rule.** Rows from the realtime feed were
   written straight to the local store. A feed repeats and reorders events,
   so a late one rolled a row back; and another device's edit replaced a row
   that had an unsynced local edit, whose queued upload then overwrote the
   server without the device showing it. Live rows now go through the same
   screening as pulled ones. One difference: an older row from a feed is
   ignored (it may only be late), while an older row from a pull is a
   conflict (the server really holds it).
20. **Nothing stopped two uploads that overlapped.** A device looks, then
   uploads; a second device can upload in between, and on a remote that
   accepts every write the later upload replaces the earlier one. The remote
   can now refuse it: with `GuardedWriteCapable` a create must find no row
   and an edit must find the row where it started, checked and written in
   one step by the backend. The engine treats the refusal as a conflict to
   resolve, not a failure, and settles it in the same cycle.
21. **A replayed upload looked like someone else's change.** When an upload
   arrived but its acknowledgement did not, the retry found the remote row
   "changed". A queued edit whose result is exactly the remote row is now
   recognized as delivered and dropped, including the first of several
   edits of one row (the rest then continue from it).
22. **A resolver's winner queued behind the edits it replaced.** The earlier
   edits were uploaded first, then the winner. The winner now replaces them:
   one upload, made on top of the remote row it was compared with.

### What is a conflict now

| Local row | Remote row | Result |
|---|---|---|
| no unsynced edit | newer version | taken as is, no resolver |
| unsynced edit | unchanged since the edit started | edit kept and uploaded, no resolver |
| unsynced edit | changed since the edit started | conflict: the resolver decides |
| any | same version, different content | conflict: the resolver decides |
| carries a vector clock | concurrent clock | conflict: the resolver decides |

Two devices whose syncs overlap can both upload before either looks. Who
finds out depends on what the backend and the rows record:

| Backend | Rows | Overlapping uploads of one row |
|---|---|---|
| refuses stale writes (`GuardedWriteCapable`) | any | the second upload is refused and goes to the resolver on that device |
| accepts every write | carry a vector clock | each device sees the clocks are concurrent: the resolver decides |
| accepts every write | no vector clock, same number of edits | same version, different content: the resolver decides |
| accepts every write | no vector clock, different number of edits | the last upload stays; the other device takes it as an update |

The last row is not something the engine can detect: neither the backend nor
the rows hold anything that says the two edits never saw each other. The
example's Supabase adapter guards its writes, so the example app is in the
first row. Each row has a test: the conflict matrix and "two devices upload
edits of one row without seeing each other" (rows one, three and four), and
`collaborative_editor_test.dart` (row two).

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
  the default direction (`pullThenPush`) the first push wins, with
  `pushThenPull` the last one does. Both are covered by a conformance test
  that gives the losing device a clock 10 minutes fast.
  `LocalPriorityResolver` on every device never converges and is only for a
  single authoritative device whose peers use `RemotePriorityResolver`.
- **Server-requested backoff, forced refetch, fail-on-conflict save, sync
  reason, sync priorities.** Added or confirmed; see §1.
- **Device-only fields** (listed here as "not a goal" before). An entity
  names the keys of its local map that never leave the device
  (`deviceOnlyFields`, or `@DatumField(deviceOnly: true)` with the
  generator). The rule has four parts, each with a test in the key-naming
  conformance suite and `live_changes_test.dart`:
  the value is stored locally; it is never uploaded (it is in the local map
  only, and it is not part of the diff); a remote row that replaces the
  local one, pulled or live, keeps it; and it is not compared, so changing
  only that field queues nothing and can never be a conflict. A second
  device gets the row without it.

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

Every item of this audit is implemented. One property depends on the
backend rather than on the engine: a backend that accepts every write, with
rows that carry no vector clock, cannot report two overlapping uploads that
differ in their number of edits (see the table in §2). Implement
`GuardedWriteCapable` in the remote adapter, or give the entity a vector
clock, to close it.

What each rule guarantees is checked by the conflict matrix and the scope
tests of the sync-stack conformance suite (`datum_test`), which every local
adapter runs; see [SYNC_SCENARIOS.md](SYNC_SCENARIOS.md).

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

## 5. State

State the engine holds or exposes is a signal from `signals_core`; streams
are only for events (something happened), never for "what is it now".

| Owner | Signals |
|---|---|
| `DatumManager` | `statusSignal`, `healthSignal` (computed), `metadataSignal`, `nextSyncTimeSignal` |
| `Datum` | `statusesSignal`, `metricsSignal`, `healthsSignal` (computed over the managers) |

- The sync engine writes the manager's status and metadata signals; inside
  `lib` a signal is read with `peek()`, so engine code never subscribes
  itself to its own state.
- The stream getters that existed before (`statusStream`, `health`,
  `allHealths`, `metrics`, ...) are views of these signals (`watchSignal`):
  current value first, then each change, closed when the owner is disposed.
- The package exports `signals_core` and stays pure Dart: no Flutter import,
  no rxdart.

`test/architecture_test.dart` enforces this too: nothing in `lib` imports
rxdart or Flutter, or declares a subject or a notifier.

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
